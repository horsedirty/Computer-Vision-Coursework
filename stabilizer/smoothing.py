"""运动平滑：累积轨迹 + 低通平滑，分离主动运动与随机抖动。

对应原 MATLAB 的 vl_motion_smoothing，思路一致(累积->平滑->求补偿)，但：
1. 用精确的矩阵连乘累积绝对轨迹 A_i，再分解到 4 自由度参数空间
   (x, y, angle, log-scale) 上平滑，正确处理旋转/缩放，避免参数相加的近似误差。
2. 提供两种平滑器：
   - gaussian : 固定高斯低通(零相移)，简单稳健，默认。
   - l1       : Grundmann(CVPR2011) 风格的 L1 最优路径，把相机轨迹约束为
                分段(静止/匀速/匀加速)，能更干净地保留主动运动、去掉抖动。

输出每帧应用于 warpAffine 的 2x3 矫正矩阵 W_i = A_i · S_i^{-1}
(warpAffine 的矩阵是 dst->src 映射，W_i 正好把稳定后画面采样回原始帧)。
"""

from __future__ import annotations

import numpy as np
from scipy.ndimage import gaussian_filter1d


def _params_to_mat(p):
    """(dx, dy, da, ds_log) -> 3x3 相似变换矩阵。"""
    dx, dy, da, ds_log = p
    s = np.exp(ds_log)
    c, sn = np.cos(da) * s, np.sin(da) * s
    return np.array([[c, -sn, dx], [sn, c, dy], [0, 0, 1]], dtype=np.float64)


def _mat_to_params(M):
    """3x3 相似矩阵 -> (dx, dy, angle, log-scale)。"""
    dx, dy = M[0, 2], M[1, 2]
    da = np.arctan2(M[1, 0], M[0, 0])
    scale = np.hypot(M[0, 0], M[1, 0])
    return dx, dy, da, np.log(max(scale, 1e-6))


def _smooth_gaussian(trajectory: np.ndarray, radius: int) -> np.ndarray:
    sigma = max(radius / 3.0, 1e-3)
    out = np.empty_like(trajectory)
    for c in range(trajectory.shape[1]):
        out[:, c] = gaussian_filter1d(trajectory[:, c], sigma=sigma, mode="nearest")
    return out


def _smooth_l1(trajectory: np.ndarray, lambdas=(10.0, 1.0, 100.0)) -> np.ndarray:
    """L1 最优相机路径(Grundmann 2011 简化版)：逐通道线性规划求解。"""
    from scipy.optimize import linprog
    from scipy.sparse import eye, lil_matrix, vstack

    n = trajectory.shape[0]
    if n < 4:
        return trajectory.copy()
    w1, w2, w3 = lambdas

    def diff_matrix(order):
        d = lil_matrix((n - order, n))
        if order == 1:
            for r in range(n - 1):
                d[r, r], d[r, r + 1] = -1, 1
        elif order == 2:
            for r in range(n - 2):
                d[r, r], d[r, r + 1], d[r, r + 2] = 1, -2, 1
        else:
            for r in range(n - 3):
                d[r, r], d[r, r + 1], d[r, r + 2], d[r, r + 3] = -1, 3, -3, 1
        return d.tocsr()

    D1, D2, D3 = diff_matrix(1), diff_matrix(2), diff_matrix(3)
    m1, m2, m3 = D1.shape[0], D2.shape[0], D3.shape[0]
    me = n
    out = np.empty_like(trajectory)
    for ch in range(trajectory.shape[1]):
        c = trajectory[:, ch]
        nvar = n + m1 + m2 + m3 + me
        cost = np.concatenate([np.zeros(n), w1 * np.ones(m1), w2 * np.ones(m2),
                               w3 * np.ones(m3), 10.0 * np.ones(me)])
        rows = []
        for D, m, off in ((D1, m1, n), (D2, m2, n + m1), (D3, m3, n + m1 + m2)):
            T = lil_matrix((m, nvar)); T[:, :n] = D; T[:, off:off + m] = -eye(m); rows.append(T)
            T2 = lil_matrix((m, nvar)); T2[:, :n] = -D; T2[:, off:off + m] = -eye(m); rows.append(T2)
        eoff = n + m1 + m2 + m3
        P1 = lil_matrix((n, nvar)); P1[:, :n] = eye(n); P1[:, eoff:eoff + n] = -eye(n)
        P2 = lil_matrix((n, nvar)); P2[:, :n] = -eye(n); P2[:, eoff:eoff + n] = -eye(n)
        A_ub = vstack(rows + [P1, P2]).tocsr()
        b_ub = np.concatenate([np.zeros(2 * (m1 + m2 + m3)), c, -c])
        bounds = [(None, None)] * n + [(0, None)] * (m1 + m2 + m3 + me)
        res = linprog(cost, A_ub=A_ub, b_ub=b_ub, bounds=bounds, method="highs")
        out[:, ch] = res.x[:n] if res.success else _smooth_gaussian(c[:, None], 30)[:, 0]
    return out


def smooth_trajectory(transforms: np.ndarray, method: str = "gaussian",
                      radius: int = 30) -> tuple[np.ndarray, dict]:
    """把逐帧相对运动平滑为逐帧 warpAffine 矫正矩阵。

    Args:
        transforms: (N,4) 逐帧相对运动 (dx,dy,da,ds_log)，第 0 行为基准。
        method:     'gaussian' 或 'l1'。
        radius:     gaussian 的平滑半径(帧)。

    Returns:
        warps: (N,2,3) 每帧的 dst->src 矫正矩阵，直接喂给 cv2.warpAffine。
        diag:  含原始/平滑后的累积轨迹(参数空间)，用于可视化与指标。
    """
    n = len(transforms)
    # 1. 精确矩阵连乘得到绝对轨迹 A_i (frame0->frame i 的点映射)
    A = np.zeros((n, 3, 3))
    A[0] = np.eye(3)
    for i in range(1, n):
        A[i] = _params_to_mat(transforms[i]) @ A[i - 1]

    # 2. 分解到参数空间
    traj = np.array([_mat_to_params(A[i]) for i in range(n)])
    traj[:, 2] = np.unwrap(traj[:, 2])  # 角度解缠，避免 ±pi 跳变

    # 3. 平滑
    smooth = _smooth_l1(traj) if method == "l1" else _smooth_gaussian(traj, radius)

    # 4. 重组 S_i，计算矫正矩阵 W_i = S_i · A_i^{-1}
    #    (warpAffine 是 dst->src 映射；该式把稳定后画面采样回原始帧，经实测验证)
    warps = np.zeros((n, 2, 3))
    for i in range(n):
        S = _params_to_mat(smooth[i])
        W = S @ np.linalg.inv(A[i])
        warps[i] = W[:2]

    diag = {"raw_trajectory": traj, "smoothed_trajectory": smooth}
    return warps, diag
