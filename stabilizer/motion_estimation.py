"""运动估计：KLT 光流跟踪 + 相似变换(RANSAC)逐帧估计。

对应原 MATLAB 的 vl_motion_estimation，做了两点提速/增强：
1. 在降采样图像上检测/跟踪特征(proc_scale)，平移分量再缩放回全分辨率，1080P 上提速数倍。
2. 用 KLT(calcOpticalFlowPyrLK)替代逐帧 SIFT 重新检测+匹配，视频相邻帧场景下又快又稳。

输出每帧相对上一帧的 4 自由度相似变换参数 (dx, dy, da, ds_log)：
    dx, dy   : 平移
    da       : 旋转角(弧度)
    ds_log   : 缩放的自然对数(便于在轨迹上做加性累积/平滑)
相似变换正好覆盖考试要求的 平移 / 旋转 / 缩放 三类主动运动。
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field

import cv2
import numpy as np


@dataclass
class MotionDiagnostics:
    total_time_ms: float = 0.0
    avg_time_per_frame_ms: float = 0.0
    inlier_ratios: list = field(default_factory=list)  # 每帧 RANSAC 内点率
    fallback_frames: list = field(default_factory=list)  # 估计失败、沿用上帧运动的帧号


# goodFeaturesToTrack 参数（多取点，给 RANSAC 更充分的样本）
_FEATURE_PARAMS = dict(maxCorners=800, qualityLevel=0.01, minDistance=12, blockSize=3)
# 金字塔 LK 光流参数
_LK_PARAMS = dict(
    winSize=(21, 21),
    maxLevel=3,
    criteria=(cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 30, 0.01),
)
# 前向-后向校验阈值（处理分辨率下的像素），超过即认为跟踪不可靠
_FB_THRESH = 1.0


def _decompose_similarity(m: np.ndarray) -> tuple[float, float, float, float]:
    """从 2x3 相似/仿射矩阵中分解出 (dx, dy, da, ds_log)。"""
    dx = float(m[0, 2])
    dy = float(m[1, 2])
    da = float(np.arctan2(m[1, 0], m[0, 0]))
    scale = float(np.sqrt(m[0, 0] ** 2 + m[1, 0] ** 2))
    ds_log = float(np.log(max(scale, 1e-6)))
    return dx, dy, da, ds_log


def estimate_motion(video_path: str, proc_scale: float = 0.5,
                    progress=None) -> tuple[np.ndarray, MotionDiagnostics]:
    """估计整段视频逐帧相对运动。

    Args:
        video_path: 输入视频路径。
        proc_scale: 特征检测/跟踪时的处理分辨率比例(0<scale<=1)。0.5 表示半分辨率估计。
        progress:   可选回调 progress(i, n)，用于进度显示。

    Returns:
        transforms: (N, 4) 数组，第 i 行是帧 i 相对帧 i-1 的 (dx, dy, da, ds_log)。
                    第 0 行为全零(基准帧)。
        diag:       MotionDiagnostics 诊断信息。
    """
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise IOError(f"无法打开视频: {video_path}")

    n_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    transforms = np.zeros((n_frames, 4), dtype=np.float64)
    diag = MotionDiagnostics()

    ok, prev = cap.read()
    if not ok:
        cap.release()
        raise IOError("视频为空或首帧读取失败")

    prev_gray = cv2.cvtColor(prev, cv2.COLOR_BGR2GRAY)
    if proc_scale != 1.0:
        prev_gray = cv2.resize(prev_gray, None, fx=proc_scale, fy=proc_scale,
                               interpolation=cv2.INTER_AREA)
    inv_scale = 1.0 / proc_scale

    last_params = np.zeros(4, dtype=np.float64)
    t0 = time.perf_counter()
    i = 1
    while True:
        ok, curr = cap.read()
        if not ok:
            break
        curr_gray = cv2.cvtColor(curr, cv2.COLOR_BGR2GRAY)
        if proc_scale != 1.0:
            curr_gray = cv2.resize(curr_gray, None, fx=proc_scale, fy=proc_scale,
                                   interpolation=cv2.INTER_AREA)

        params = last_params  # 默认回退值：沿用上一帧运动(常速预测)，避免单位阵造成轨迹跳变
        inlier_ratio = 0.0
        fell_back = True

        prev_pts = cv2.goodFeaturesToTrack(prev_gray, mask=None, **_FEATURE_PARAMS)
        if prev_pts is not None and len(prev_pts) >= 6:
            curr_pts, status, _ = cv2.calcOpticalFlowPyrLK(
                prev_gray, curr_gray, prev_pts, None, **_LK_PARAMS)
            if curr_pts is not None:
                # 前向-后向校验：从 curr 反向跟回 prev，保留回跳误差小的点
                back_pts, status_b, _ = cv2.calcOpticalFlowPyrLK(
                    curr_gray, prev_gray, curr_pts, None, **_LK_PARAMS)
                fb_err = np.linalg.norm(prev_pts - back_pts, axis=2).flatten()
                ok_mask = (status.flatten() == 1) & (status_b.flatten() == 1) & (fb_err < _FB_THRESH)
                good_prev = prev_pts[ok_mask]
                good_curr = curr_pts[ok_mask]
                if len(good_prev) >= 6:
                    m, inliers = cv2.estimateAffinePartial2D(
                        good_prev, good_curr, method=cv2.RANSAC,
                        ransacReprojThreshold=3.0, maxIters=2000, confidence=0.99)
                    if m is not None:
                        dx, dy, da, ds_log = _decompose_similarity(m)
                        # 平移分量在降采样尺度上，缩放回全分辨率；旋转/缩放与尺度无关
                        params = np.array([dx * inv_scale, dy * inv_scale, da, ds_log])
                        inlier_ratio = float(np.mean(inliers)) if inliers is not None else 0.0
                        fell_back = False

        transforms[i] = params
        last_params = params
        diag.inlier_ratios.append(inlier_ratio)
        if fell_back:
            diag.fallback_frames.append(i)

        prev_gray = curr_gray
        if progress is not None:
            progress(i, n_frames)
        i += 1

    cap.release()
    elapsed_ms = (time.perf_counter() - t0) * 1000.0
    diag.total_time_ms = elapsed_ms
    diag.avg_time_per_frame_ms = elapsed_ms / max(1, i - 1)
    # 真实帧数可能与 metadata 不符，按实际读到的裁剪
    return transforms[:i], diag
