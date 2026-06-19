"""帧合成：按矫正矩阵 warp 重排 + 自适应裁剪 + 锐化 + 编码输出。

对应原 MATLAB 的 vl_frame_synthesis。相似变换 warp 同时补偿平移/旋转/缩放；
裁剪采用【自适应】中心 zoom-in：根据每帧矫正量自动算出刚好藏住黑边的最小放大倍数，
既不露黑边(肉眼很敏感)，又不过度裁剪损失画面与分辨率。
warps 已是 dst->src 映射，可直接喂给 cv2.warpAffine。
"""

from __future__ import annotations

import time

import cv2
import numpy as np

from border_fill import fill_frame


def _frame_min_zoom(W: np.ndarray, w: int, h: int, zmax: float = 4.0) -> float:
    """单帧：算出让输出矩形 4 角都落回原始画面内所需的最小中心放大倍数。

    直接对 zoom 做二分搜索 + 实际坐标覆盖检测，鲁棒(不依赖解析式，避免
    平移过大、中心映射到画外等边界情形下的估计错误)。
    """
    if W.shape == (2, 3):
        W = np.vstack([W, [0, 0, 1]])
    cx, cy = w / 2.0, h / 2.0

    def covered(z):
        for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            x = cx + sx * (w / 2.0) / z
            y = cy + sy * (h / 2.0) / z
            s = W @ np.array([x, y, 1.0])
            if not (0.0 <= s[0] <= w and 0.0 <= s[1] <= h):
                return False
        return True

    if covered(1.0):
        return 1.0
    lo, hi = 1.0, zmax
    for _ in range(30):
        mid = (lo + hi) / 2.0
        if covered(mid):
            hi = mid
        else:
            lo = mid
    return hi


def _warp_decompose(W):
    """2x3 warp -> (dx, dy, da, ds_log)。"""
    return (W[0, 2], W[1, 2], np.arctan2(W[1, 0], W[0, 0]),
            np.log(max(np.hypot(W[0, 0], W[1, 0]), 1e-6)))


def _warp_compose(p):
    """(dx, dy, da, ds_log) -> 2x3 warp。"""
    dx, dy, da, ds = p
    s = np.exp(ds)
    c, sn = np.cos(da) * s, np.sin(da) * s
    return np.array([[c, -sn, dx], [sn, c, dy]], dtype=np.float64)


def damp_warps(warps: np.ndarray, w: int, h: int, max_zoom: float) -> np.ndarray:
    """把每帧矫正量限制在裁剪预算内：若某帧矫正过大(需 zoom>max_zoom 才能藏黑边)，
    就按比例把该帧的矫正向"不矫正"收缩，直到刚好落入预算。

    效果：快速摇摄等大幅运动时少矫正一点(那本就是主动运动)，换取
    全程固定小裁剪、画面贴近原视频、且【永不出现黑边】。
    """
    out = np.empty_like(warps)
    for i in range(len(warps)):
        p = np.array(_warp_decompose(warps[i]))
        if _frame_min_zoom(np.vstack([warps[i], [0, 0, 1]]), w, h) <= max_zoom:
            out[i] = warps[i]
            continue
        lo, hi = 0.0, 1.0  # 二分搜索最大可保留的矫正比例 alpha
        for _ in range(24):
            mid = (lo + hi) / 2
            Wm = _warp_compose(p * mid)
            if _frame_min_zoom(np.vstack([Wm, [0, 0, 1]]), w, h) <= max_zoom:
                lo = mid
            else:
                hi = mid
        out[i] = _warp_compose(p * lo)
    return out


def compute_auto_zoom(warps: np.ndarray, w: int, h: int,
                      percentile: float = 100.0, cap: float = 1.30,
                      floor: float = 1.02) -> float:
    """全局自适应放大倍数：取各帧所需 zoom 的(高)分位数，clamp 到 [floor, cap]。

    默认 percentile=100，即覆盖所有帧 —— 保证没有任何一帧露出黑边/镜像边缘
    (肉眼对边缘伪影非常敏感)。cap 防止个别病态帧把整段过度放大；超过 cap 的
    极少数帧用纯黑填充(干净，不像镜像那样诡异)。
    """
    zs = np.array([_frame_min_zoom(np.vstack([warps[i], [0, 0, 1]]), w, h)
                   for i in range(len(warps))])
    z = float(np.percentile(zs, percentile))
    return float(np.clip(z, floor, cap))


def _open_writer(path: str, fps: float, size: tuple[int, int]) -> cv2.VideoWriter:
    """优先用 H.264(avc1)，兼容性最好(IDE/浏览器/各播放器都能开)；失败回退 mp4v。"""
    w = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*"avc1"), fps, size)
    if not w.isOpened():
        w = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*"mp4v"), fps, size)
    if not w.isOpened():
        raise IOError(f"无法创建输出视频: {path}")
    return w


def _label(img, text):
    """在画面左上角加白字黑边标签(仅 ASCII，cv2 不支持中文)。"""
    cv2.putText(img, text, (12, 34), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 0, 0), 5, cv2.LINE_AA)
    cv2.putText(img, text, (12, 34), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (255, 255, 255), 2, cv2.LINE_AA)
    return img


class _FrameWindow:
    """顺序读取视频并缓存一个滑动窗口的帧，供时域补边随机访问邻帧。

    只支持随 i 递增的近邻访问([i-radius, i+radius])：前读到 i+radius、
    丢弃 < i-radius，内存占用 O(2·radius) 帧。
    """

    def __init__(self, cap: cv2.VideoCapture, n: int):
        self.cap, self.n = cap, n
        self.cache: dict[int, np.ndarray | None] = {}
        self.next_read = 0

    def get(self, k: int):
        if k < 0 or k >= self.n:
            return None
        while self.next_read <= k:
            ok, fr = self.cap.read()
            self.cache[self.next_read] = fr if ok else None
            self.next_read += 1
        return self.cache.get(k)

    def evict_below(self, lo: int):
        for key in [kk for kk in self.cache if kk < lo]:
            del self.cache[key]


def _apply_sharpen(img, amount):
    blur = cv2.GaussianBlur(img, (0, 0), 1.5)
    return cv2.addWeighted(img, 1 + amount, blur, -amount, 0)


def synthesize(video_path: str, warps: np.ndarray, output_path: str,
               zoom: float | None = None, crop_limit: float = 1.10,
               sharpen: bool = True, sharpen_amount: float = 0.6,
               compare_path: str | None = None, progress=None,
               border_mode: str = "crop", abs_transforms: np.ndarray | None = None,
               fill_window: int = 20, fill_feather: int = 8) -> dict:
    """应用逐帧矫正矩阵生成稳定视频。

    Args:
        video_path: 输入视频。
        warps:      (N,2,3) 每帧 dst->src 矫正矩阵。
        output_path: 输出 mp4 路径。
        zoom:       中心放大倍数。None 表示自适应自动计算（仅 crop 模式）。
        crop_limit: 裁剪预算(最大放大倍数)。矫正量会被限制在此预算内，
                    保证全程小裁剪、画面贴近原视频、永不出现黑边。1.10≈每边裁4.5%。
        sharpen:    是否做 USM 锐化补偿插值损失。
        sharpen_amount: 锐化强度(0.6 较柔和，避免塑料感)。
        compare_path: 若给定，额外输出 [原始 | 去抖] 左右并排对比视频。
        progress:   可选进度回调 progress(i, n)。
        border_mode: "crop"(默认,中心裁剪缩放藏黑边) | "inpaint"(全幅,
                     用相邻帧像素 warp 过来填补黑边,不裁剪不损失视野/分辨率)。
        abs_transforms: (N,3,3) 绝对轨迹 A_i，border_mode="inpaint" 时必需。
        fill_window: 补边时向前/后各取多少帧作为像素来源。
        fill_feather: 补边接缝羽化半径(像素)。
    """
    cap_v = cv2.VideoCapture(video_path)
    if not cap_v.isOpened():
        raise IOError(f"无法打开视频: {video_path}")

    w = int(cap_v.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap_v.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = cap_v.get(cv2.CAP_PROP_FPS) or 30.0
    n = len(warps)
    cx, cy = w / 2.0, h / 2.0

    writer = _open_writer(output_path, fps, (w, h))
    cmp_writer = _open_writer(compare_path, fps, (2 * w + 4, h)) if compare_path else None
    divider = np.full((h, 4, 3), 80, np.uint8)  # 对比视频中间灰色分隔条
    t0 = time.perf_counter()

    if border_mode == "inpaint":
        if abs_transforms is None:
            raise ValueError("border_mode='inpaint' 需要传入 abs_transforms (绝对轨迹 A)")
        win = _FrameWindow(cap_v, n)
        hole_ratios = []
        for i in range(n):
            orig = win.get(i)  # 触发顺序读取，缓存窗口内邻帧
            if orig is None:
                break
            win.get(min(n - 1, i + fill_window))  # 预读到右窗口
            win.evict_below(i - fill_window)
            stabilized, hole = fill_frame(i, win.get, warps, abs_transforms, w, h,
                                          window=fill_window, feather=fill_feather)
            hole_ratios.append(hole)
            if sharpen:
                stabilized = _apply_sharpen(stabilized, sharpen_amount)
            writer.write(stabilized)
            if cmp_writer is not None:
                side = np.hstack([_label(orig.copy(), "Original"),
                                  divider, _label(stabilized.copy(), "Stabilized")])
                cmp_writer.write(side)
            if progress is not None:
                progress(i, n)
        cap_v.release(); writer.release()
        if cmp_writer is not None:
            cmp_writer.release()
        return {"total_time_ms": (time.perf_counter() - t0) * 1000.0, "zoom": 1.0,
                "mode": "inpaint",
                "mean_hole_ratio": float(np.mean(hole_ratios)) if hole_ratios else 0.0,
                "max_hole_ratio": float(np.max(hole_ratios)) if hole_ratios else 0.0}

    # ---- crop 模式（默认）：中心裁剪缩放藏黑边 ----
    # 把矫正量限制在裁剪预算内，保证小裁剪、贴近原画、无黑边。
    # 阻尼到略紧的预算(留 2% 余量)，再施加实际放大，确保边界不残留黑边像素。
    HEADROOM = 1.02
    warps = damp_warps(warps, w, h, crop_limit / HEADROOM)
    if zoom is None:
        # 阻尼后所有帧都落入预算，自适应取实际最大需求并加余量(仍不超过 crop_limit)
        zoom = compute_auto_zoom(warps, w, h, cap=crop_limit / HEADROOM, floor=1.02) * HEADROOM
    Zs = np.array([[1.0 / zoom, 0, cx * (1 - 1.0 / zoom)],
                   [0, 1.0 / zoom, cy * (1 - 1.0 / zoom)],
                   [0, 0, 1]], dtype=np.float64)

    for i in range(n):
        ok, frame = cap_v.read()
        if not ok:
            break
        W = np.vstack([warps[i], [0, 0, 1]])
        M = (W @ Zs)[:2]  # 先 zoom-in，再 W 采样回原图
        # 黑色填充：自适应 zoom 已覆盖绝大多数帧，残留极少数边缘用纯黑(干净)而非镜像(诡异)
        stabilized = cv2.warpAffine(frame, M, (w, h),
                                    flags=cv2.INTER_CUBIC,
                                    borderMode=cv2.BORDER_CONSTANT, borderValue=0)
        if sharpen:
            stabilized = _apply_sharpen(stabilized, sharpen_amount)
        writer.write(stabilized)

        if cmp_writer is not None:
            side = np.hstack([_label(frame.copy(), "Original"),
                              divider, _label(stabilized.copy(), "Stabilized")])
            cmp_writer.write(side)

        if progress is not None:
            progress(i, n)

    cap_v.release()
    writer.release()
    if cmp_writer is not None:
        cmp_writer.release()
    return {"total_time_ms": (time.perf_counter() - t0) * 1000.0, "zoom": zoom}
