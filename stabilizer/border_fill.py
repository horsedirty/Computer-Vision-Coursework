"""时域运动修补（full-frame video stabilization with motion inpainting）。

思路对应 Matsushita et al. 2006《Full-Frame Video Stabilization with Motion
Inpainting》以及 OpenCV videostab 的 MotionInpainter/ConsistentMosaicInpainter：
不裁剪、不缩放，保留整幅画面；稳定后每帧边缘出现的黑边空洞，用【相邻帧】的
真实像素 warp 过来补齐，从而做到全分辨率、全视野、无黑边。

与本项目已有流水线的耦合点（关键、避免重推导坐标系约定）：
    已有的逐帧 dst->src 矫正矩阵 W_i 经实测验证：稳定帧 O_i(x) = F_i(W_i · x)。
    设绝对轨迹 A_i（frame0->frame i 的点映射，由 smoothing 提供）。世界同一点在
    F_i 中位置 p_i = W_i·x，在 F_j 中位置 p_j = (A_j A_i^{-1}) p_i。故用邻帧 j 的
    源像素填补当前画布 x 处空洞的采样矩阵为：
        G_{i<-j} = A_j · A_i^{-1} · W_i          （3x3，喂给 warpAffine 取 [:2]）
    j==i 时 G == W_i，与主路径自洽。无需引入平滑位姿 S，直接复用已验证的 W。
"""

from __future__ import annotations

import cv2
import numpy as np


def neighbor_transform(W_i_full: np.ndarray, A_i: np.ndarray,
                       A_j: np.ndarray) -> np.ndarray:
    """邻帧 j 的源图 -> 当前帧 i 稳定画布的采样矩阵 G_{i<-j}（3x3）。

    G = A_j · A_i^{-1} · W_i。同帧 (A_j==A_i) 时退化为 W_i。
    """
    if W_i_full.shape == (2, 3):
        W_i_full = np.vstack([W_i_full, [0, 0, 1]])
    return A_j @ np.linalg.inv(A_i) @ W_i_full


def _warp_with_mask(frame: np.ndarray, M3: np.ndarray, w: int, h: int,
                    roi: tuple[int, int, int, int] | None = None):
    """按 3x3 矩阵 M 把 frame warp 到画布，返回 (画面, 有效像素 mask)。

    mask 用同一矩阵 warp 一张全白图得到，标记哪些输出像素真有源像素覆盖。
    roi=(x0,y0,rw,rh) 时只渲染该目标矩形（黑边只在画面边缘，按需渲染窄带可省大量算力）。
    """
    M = M3[:2].copy()
    if roi is None:
        dsize = (w, h)
    else:
        x0, y0, rw, rh = roi
        M[0, 2] -= x0
        M[1, 2] -= y0
        dsize = (rw, rh)
    warped = cv2.warpAffine(frame, M, dsize, flags=cv2.INTER_CUBIC,
                            borderMode=cv2.BORDER_CONSTANT, borderValue=0)
    ones = np.full(frame.shape[:2], 255, np.uint8)
    cover = cv2.warpAffine(ones, M, dsize, flags=cv2.INTER_NEAREST,
                           borderMode=cv2.BORDER_CONSTANT, borderValue=0)
    return warped, cover > 127


def _feather_seam(result: np.ndarray, base_mask: np.ndarray,
                  filled: np.ndarray, feather: int) -> None:
    """对“原内容 ↔ 填充内容”交界窄带做局部高斯柔化（就地修改 result）。"""
    fill_region = filled & (~base_mask)
    if feather <= 0 or not fill_region.any():
        return
    k = 2 * feather + 1
    near_base = cv2.dilate(base_mask.astype(np.uint8), np.ones((k, k), np.uint8)) > 0
    near_fill = cv2.dilate(fill_region.astype(np.uint8), np.ones((k, k), np.uint8)) > 0
    band = near_base & near_fill & filled
    if band.any():
        blurred = cv2.GaussianBlur(result, (0, 0), feather / 2.0)
        result[band] = blurred[band]


def temporal_fill(base: np.ndarray, base_mask: np.ndarray,
                  contributions, feather: int = 8):
    """用若干邻帧贡献填补当前帧黑边空洞。

    Args:
        base:      当前稳定帧（含黑边空洞），HxWx3 uint8。
        base_mask: 当前帧有效像素 mask，HxW bool（True=有内容）。
        contributions: [(img, mask), ...]，每项是一张已对齐到当前画布的邻帧贡献，
                       建议按与当前帧的时间距离从近到远排序（近邻优先、画质更接近）。
        feather:   接缝羽化半径（像素），>0 时对原内容/填充内容交界做轻微柔化。

    Returns:
        filled:    填补后的帧，HxWx3 uint8。
        hole_mask: 仍未被任何来源覆盖的空洞，HxW bool（True=空洞）。
    """
    result = base.astype(np.float32).copy()
    filled = base_mask.copy()
    for img, m in contributions:
        newly = m & (~filled)
        if not newly.any():
            continue
        result[newly] = img[newly].astype(np.float32)
        filled |= m  # 近邻优先：已填区域不被更远的邻帧覆盖

    hole_mask = ~filled
    # 接缝柔化：仅在“原内容 ↔ 填充内容”交界窄带内做局部高斯混合，削弱硬边。
    _feather_seam(result, base_mask, filled, feather)
    return np.clip(result, 0, 255).astype(np.uint8), hole_mask


def fill_frame(idx: int, get_frame, warps: np.ndarray, A: np.ndarray,
               w: int, h: int, window: int = 20, feather: int = 8,
               inpaint_residual: bool = True, max_sources: int = 12,
               residual_eps: float = 0.002):
    """生成单帧的全幅（无黑边）稳定结果。

    Args:
        idx:       当前帧序号。
        get_frame: 取帧函数 get_frame(k)->BGR 帧或 None（越界返回 None）。
        warps:     (N,2,3) 每帧 dst->src 矫正矩阵。
        A:         (N,3,3) 绝对轨迹矩阵（smoothing 提供）。
        window:    向前/后各取多少帧作为补边来源。
        feather:   接缝羽化半径。
        inpaint_residual: 残留极小空洞是否用 cv2.inpaint 收尾。

    Returns:
        (filled_frame, hole_ratio)：填补后帧 与 残留空洞像素占比。
    """
    n = len(warps)
    W_i = np.vstack([warps[idx], [0, 0, 1]])
    cur = get_frame(idx)
    base, base_mask = _warp_with_mask(cur, W_i, w, h)

    result = base.astype(np.float32).copy()
    filled = base_mask.copy()
    if not filled.all():
        # 黑边只在画面边缘 —— 取所有空洞的外接矩形(带余量)，邻帧只 warp 进这个窄带，
        # 省去整幅 1080p 反复重采样的开销。
        ys, xs = np.where(~base_mask)
        mgn = feather + 2
        x0 = max(0, int(xs.min()) - mgn); x1 = min(w, int(xs.max()) + 1 + mgn)
        y0 = max(0, int(ys.min()) - mgn); y1 = min(h, int(ys.max()) + 1 + mgn)
        roi = (x0, y0, x1 - x0, y1 - y0)
        res_roi = result[y0:y1, x0:x1]
        fill_roi = filled[y0:y1, x0:x1]
        # 近邻优先增量填补。最近邻与当前帧重叠最多、曝光最接近、画质最好；
        # 远帧极少能补上近邻补不到的角落，故限制来源数并在残留极小时收手交给 inpaint。
        eps_px = residual_eps * w * h
        order = sorted(range(max(0, idx - window), min(n, idx + window + 1)),
                       key=lambda j: abs(j - idx))
        used = 0
        for j in order:
            if j == idx:
                continue
            if used >= max_sources or (~fill_roi).sum() < eps_px:
                break
            fj = get_frame(j)
            if fj is None:
                continue
            G = neighbor_transform(W_i, A[idx], A[j])
            img, m = _warp_with_mask(fj, G, w, h, roi=roi)
            newly = m & (~fill_roi)
            if not newly.any():
                continue
            res_roi[newly] = img[newly].astype(np.float32)
            fill_roi |= m
            used += 1

    hole = ~filled
    _feather_seam(result, base_mask, filled, feather)
    out = np.clip(result, 0, 255).astype(np.uint8)
    if inpaint_residual and hole.any():
        out = cv2.inpaint(out, hole.astype(np.uint8) * 255, 3, cv2.INPAINT_TELEA)
    return out, float(hole.mean())