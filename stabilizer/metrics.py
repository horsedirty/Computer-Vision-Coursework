"""评测指标：有效防抖时长占比 + 抖动能量。

考试评分的核心是肉眼"平稳的时长占比"。这里给出一个可量化的近似判据：
对【处理后】视频重新估计逐帧运动，分离出高频抖动分量(去掉主动运动的低频趋势)，
某一帧的残余抖动幅度低于阈值即视为"平稳"。平稳帧数 / 总帧数 = 有效防抖时长占比。

主动的平移/旋转/缩放是低频趋势，会被减掉；只有手抖那种高频残差会被统计为抖动，
因此该指标不会因为相机正常运动而误判。
"""

from __future__ import annotations

import numpy as np
from scipy.ndimage import gaussian_filter1d

from motion_estimation import estimate_motion


def stabilization_ratio(video_path: str, jitter_thresh_px: float = 1.0,
                        trend_radius: int = 12, proc_scale: float = 0.5) -> dict:
    """计算视频的有效防抖时长占比。

    Args:
        video_path: 待评测视频(通常是处理后的输出)。
        jitter_thresh_px: 判定"平稳"的高频抖动阈值(像素)。越严越接近肉眼。
        trend_radius: 提取主动运动低频趋势的高斯半径(帧)。
        proc_scale: 运动估计的处理分辨率。

    Returns:
        dict: ratio(占比)、stable_frames、total_frames、mean_jitter_px、per_frame_jitter。
    """
    transforms, _ = estimate_motion(video_path, proc_scale=proc_scale)
    n = len(transforms)
    if n < 3:
        return {"ratio": 1.0, "stable_frames": n, "total_frames": n,
                "mean_jitter_px": 0.0, "per_frame_jitter": np.zeros(n)}

    # 用图像半对角线把 角度/缩放 抖动折算成边缘像素位移，和平移统一量纲
    import cv2
    cap = cv2.VideoCapture(video_path)
    w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    cap.release()
    radius = 0.5 * np.hypot(w, h)

    # 逐帧相对运动在像素量纲上的等效幅度
    dx, dy = transforms[:, 0], transforms[:, 1]
    da, ds = transforms[:, 2], transforms[:, 3]
    motion = np.stack([dx, dy, da * radius, ds * radius], axis=1)

    # 低频趋势 = 主动运动；残差 = 抖动
    sigma = max(trend_radius / 3.0, 1e-3)
    trend = np.stack([gaussian_filter1d(motion[:, c], sigma=sigma, mode="reflect")
                      for c in range(motion.shape[1])], axis=1)
    residual = motion - trend
    per_frame_jitter = np.linalg.norm(residual, axis=1)

    stable = per_frame_jitter < jitter_thresh_px
    return {
        "ratio": float(np.mean(stable)),
        "stable_frames": int(np.sum(stable)),
        "total_frames": int(n),
        "mean_jitter_px": float(np.mean(per_frame_jitter)),
        "per_frame_jitter": per_frame_jitter,
    }
