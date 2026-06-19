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


def _frame_min_zoom(W: np.ndarray, w: int, h: int) -> float:
    """单帧：算出让输出矩形 4 角都落在原始画面内所需的最小中心放大倍数。"""
    cx, cy = w / 2.0, h / 2.0
    A = W[:, :2]                      # 2x2 线性部分
    p0 = W @ np.array([cx, cy, 1.0])  # 输出中心映射回原图的位置(近似在画面内)
    t_feasible = 1.0
    for xx, yy in ((0, 0), (w, 0), (w, h), (0, h)):
        d = A @ np.array([xx - cx, yy - cy])
        # 输出角 c 缩放为 center + (c-center)*t (t=1/zoom)，映射回原图 s = p0 + t*d
        # 求最大 t 使 s 仍在 [0,w]x[0,h] 内
        t_lim = 1.0
        for comp, hi in ((0, w), (1, h)):
            pc, dc = p0[comp], d[comp]
            if dc > 1e-9:
                t_lim = min(t_lim, (hi - pc) / dc)
            elif dc < -1e-9:
                t_lim = min(t_lim, (0.0 - pc) / dc)
        t_feasible = min(t_feasible, max(t_lim, 1e-3))
    return 1.0 / t_feasible


def compute_auto_zoom(warps: np.ndarray, w: int, h: int,
                      percentile: float = 98.0, cap: float = 1.30,
                      floor: float = 1.02) -> float:
    """全局自适应放大倍数：取各帧所需 zoom 的高分位数，clamp 到 [floor, cap]。

    用分位数而非最大值，避免个别极端抖动帧把整段视频都过度放大；
    那几帧可能露出极轻微边缘，但整体画面保留更多、更清晰。
    """
    zs = np.array([_frame_min_zoom(np.vstack([warps[i], [0, 0, 1]]), w, h)
                   for i in range(len(warps))])
    z = float(np.percentile(zs, percentile))
    return float(np.clip(z, floor, cap))


def synthesize(video_path: str, warps: np.ndarray, output_path: str,
               zoom: float | None = None, min_crop: float = 0.0,
               sharpen: bool = True, sharpen_amount: float = 0.6,
               progress=None) -> dict:
    """应用逐帧矫正矩阵生成稳定视频。

    Args:
        video_path: 输入视频。
        warps:      (N,2,3) 每帧 dst->src 矫正矩阵。
        output_path: 输出 mp4 路径。
        zoom:       中心放大倍数。None 表示自适应自动计算。
        min_crop:   自适应模式下的最小裁剪比例(转成最小 zoom 下限)。
        sharpen:    是否做 USM 锐化补偿插值损失。
        sharpen_amount: 锐化强度(0.6 较柔和，避免塑料感)。
        progress:   可选进度回调 progress(i, n)。
    """
    cap_v = cv2.VideoCapture(video_path)
    if not cap_v.isOpened():
        raise IOError(f"无法打开视频: {video_path}")

    w = int(cap_v.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap_v.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = cap_v.get(cv2.CAP_PROP_FPS) or 30.0
    n = len(warps)
    cx, cy = w / 2.0, h / 2.0

    if zoom is None:
        zoom = compute_auto_zoom(warps, w, h, floor=max(1.02, 1.0 + 2.0 * min_crop))
    Zs = np.array([[1.0 / zoom, 0, cx * (1 - 1.0 / zoom)],
                   [0, 1.0 / zoom, cy * (1 - 1.0 / zoom)],
                   [0, 0, 1]], dtype=np.float64)

    writer = cv2.VideoWriter(output_path, cv2.VideoWriter_fourcc(*"mp4v"), fps, (w, h))
    if not writer.isOpened():
        cap_v.release()
        raise IOError(f"无法创建输出视频: {output_path}")

    t0 = time.perf_counter()
    for i in range(n):
        ok, frame = cap_v.read()
        if not ok:
            break
        W = np.vstack([warps[i], [0, 0, 1]])
        M = (W @ Zs)[:2]  # 先 zoom-in，再 W 采样回原图
        stabilized = cv2.warpAffine(frame, M, (w, h),
                                    flags=cv2.INTER_CUBIC,
                                    borderMode=cv2.BORDER_REFLECT101)
        if sharpen:
            blur = cv2.GaussianBlur(stabilized, (0, 0), 1.5)
            stabilized = cv2.addWeighted(stabilized, 1 + sharpen_amount,
                                         blur, -sharpen_amount, 0)
        writer.write(stabilized)
        if progress is not None:
            progress(i, n)

    cap_v.release()
    writer.release()
    return {"total_time_ms": (time.perf_counter() - t0) * 1000.0, "zoom": zoom}
