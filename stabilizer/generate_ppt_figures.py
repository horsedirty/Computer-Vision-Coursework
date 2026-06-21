"""生成 PPT 第 4/5/6 页配图（也用于论文 figure 补充）：

  fig1  klt_tracking_walking1.png
        真实手持步行视频 walking1.mp4 上的 KLT 光流跟踪连线图：
        背景点(RANSAC 内点)绿色保留并画运动矢量；前景/不可靠点
        (前向-后向校验失败 或 RANSAC 外点)红色被剔除。

  fig2  synth_handheld_walking_trajectory_gauss.png   (高斯平滑)
  fig3  synth_handheld_walking_trajectory_l1.png      (L1 平滑)
        合成手持步行集(带真值)的绝对运动轨迹：
        红=估计原始 · 蓝=平滑 · 绿虚=真值。

合成轨迹图选用 synth_handheld_walking：与 walking1 同为手持步行场景，
且带 Ground Truth，可如实绘制真值线（真实视频 walking1 无真值）。
"""
from __future__ import annotations

import os

import cv2
import numpy as np
import scipy.io as sio
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D

from smoothing import smooth_trajectory

IMG_DIR = "../docs/航空学报latex模版/AAAS/image"
WALKING = "../data/test_videos/walking1.mp4"
SYNTH_VID = "../data/test_videos/analog_data/synth_handheld_walking.mp4"
SYNTH_GT = "../data/test_videos/analog_data/synth_handheld_walking_groundtruth.mat"

# 与 motion_estimation.py 一致的特征/光流参数（此处在全分辨率上跑，便于出清晰大图）
_FEATURE_PARAMS = dict(maxCorners=1200, qualityLevel=0.01, minDistance=14, blockSize=3)
_LK_PARAMS = dict(winSize=(31, 31), maxLevel=3,
                  criteria=(cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 30, 0.01))
_FB_THRESH = 2.0       # 全分辨率下的前向-后向回跳阈值(px)
_RANSAC_THRESH = 4.0   # 全分辨率下的 RANSAC 重投影阈值(px)
_GAP = 3               # 取相隔 GAP 帧成对，使运动矢量在图上清晰可见


# ----------------------------------------------------------------------------
# Figure 1: KLT 跟踪连线图
# ----------------------------------------------------------------------------
def _track_pair(g0, g1):
    """对一对灰度帧做 检测 + KLT + 前向后向校验 + RANSAC，返回各类点。

    Returns dict 或 None: prev/curr 对应点，fb_ok 掩码，ransac_inlier 掩码。
    """
    p0 = cv2.goodFeaturesToTrack(g0, mask=None, **_FEATURE_PARAMS)
    if p0 is None or len(p0) < 12:
        return None
    p1, st, _ = cv2.calcOpticalFlowPyrLK(g0, g1, p0, None, **_LK_PARAMS)
    if p1 is None:
        return None
    p0b, stb, _ = cv2.calcOpticalFlowPyrLK(g1, g0, p1, None, **_LK_PARAMS)
    fb = np.linalg.norm(p0 - p0b, axis=2).ravel()
    tracked = (st.ravel() == 1) & (stb.ravel() == 1)        # LK 成功跟踪
    fb_ok = tracked & (fb < _FB_THRESH)                     # 通过前向-后向校验
    prev = p0.reshape(-1, 2)
    curr = p1.reshape(-1, 2)

    ransac_inlier = np.zeros(len(prev), dtype=bool)
    idx = np.where(fb_ok)[0]
    if len(idx) >= 12:
        m, inl = cv2.estimateAffinePartial2D(
            prev[idx], curr[idx], method=cv2.RANSAC,
            ransacReprojThreshold=_RANSAC_THRESH, maxIters=2000, confidence=0.99)
        if inl is not None:
            ransac_inlier[idx[inl.ravel() == 1]] = True
    return dict(prev=prev, curr=curr, tracked=tracked, fb_ok=fb_ok,
                ransac_inlier=ransac_inlier)


def make_klt_figure():
    cap = cv2.VideoCapture(WALKING)
    n = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    frames = {}
    # 缓存抽样帧的灰度图与彩色图
    sample_ids = list(range(0, n - _GAP, 5))
    need = set(sample_ids) | {i + _GAP for i in sample_ids}
    i = 0
    while True:
        ok, fr = cap.read()
        if not ok:
            break
        if i in need:
            frames[i] = fr
        i += 1
    cap.release()

    # 选帧标准：要讲清"背景保留 / 前景剔除"的故事，需要
    #   (a) 背景内点占绝对多数(RANSAC 找到了可靠的全局模型)；
    #   (b) 一簇"通过了前向后向校验、却与背景模型不一致"的点 —— 这才是真正
    #       独立运动的前景(行人)，被 RANSAC 当外点剔除，空间上成团。
    # 故评分 = 前景点的局部聚集密度(在内点占优的前提下)。
    def cluster_density(pts):
        if len(pts) < 12:
            return 0
        cell = 120.0  # 像素网格
        from collections import Counter
        cnt = Counter((int(x // cell), int(y // cell)) for x, y in pts)
        best_local = 0
        for (cx, cy) in cnt:                # 统计每个 3x3 邻域窗口内的前景点数
            s = sum(cnt.get((cx + dx, cy + dy), 0) for dx in (-1, 0, 1) for dy in (-1, 0, 1))
            best_local = max(best_local, s)
        return best_local

    best = None
    for s in sample_ids:
        f0, f1 = frames.get(s), frames.get(s + _GAP)
        if f0 is None or f1 is None:
            continue
        g0 = cv2.cvtColor(f0, cv2.COLOR_BGR2GRAY)
        g1 = cv2.cvtColor(f1, cv2.COLOR_BGR2GRAY)
        r = _track_pair(g0, g1)
        if r is None:
            continue
        fb_ok = r["fb_ok"]; inl = r["ransac_inlier"]
        n_in = int(inl.sum())
        n_fb = int(fb_ok.sum())
        fg = fb_ok & ~inl                    # 前景: 跟踪可靠但与背景模型不一致
        if n_in < 250 or n_fb == 0 or n_in / n_fb < 0.6:
            continue                         # 背景必须占绝对多数
        score = cluster_density(r["curr"][fg])
        if best is None or score > best[0]:
            best = (score, s, r)

    if best is None:
        raise RuntimeError("未能在 walking1 上找到合适的 KLT 演示帧")
    _, s, r = best
    base = cv2.cvtColor(frames[s], cv2.COLOR_BGR2RGB)
    prev, curr = r["prev"], r["curr"]
    inlier = r["ransac_inlier"]
    rejected = r["fb_ok"] & ~inlier         # 前景: 通过校验但被 RANSAC 判为外点

    H, W = base.shape[:2]
    fig, ax = plt.subplots(figsize=(W / 200, H / 200), dpi=200)
    ax.imshow(base)
    ax.set_xlim(0, W); ax.set_ylim(H, 0); ax.axis("off")

    # 背景内点：绿色运动矢量 + 端点
    gi = np.where(inlier)[0]
    for j in gi:
        x0, y0 = prev[j]; x1, y1 = curr[j]
        ax.plot([x0, x1], [y0, y1], color="#1fdb1f", lw=1.1, alpha=0.9, solid_capstyle="round")
    ax.scatter(curr[gi, 0], curr[gi, 1], s=7, c="#0a8f0a", zorder=3)

    # 被剔除点：红色 ×（前景/不可靠）
    ri = np.where(rejected)[0]
    for j in ri:
        x0, y0 = prev[j]; x1, y1 = curr[j]
        ax.plot([x0, x1], [y0, y1], color="#ff4d4d", lw=1.1, alpha=0.85, solid_capstyle="round")
    ax.scatter(curr[ri, 0], curr[ri, 1], s=42, c="#e60000", marker="x", linewidths=1.6, zorder=4)

    handles = [
        Line2D([0], [0], color="#1fdb1f", marker="o", markerfacecolor="#0a8f0a",
               markersize=6, lw=2, label=f"Inlier · background, kept by RANSAC  (n={len(gi)})"),
        Line2D([0], [0], color="#ff4d4d", marker="x", markersize=8, lw=2,
               markeredgewidth=2, label=f"Outlier · independently-moving foreground, rejected by RANSAC  (n={len(ri)})"),
    ]
    leg = ax.legend(handles=handles, loc="upper center", bbox_to_anchor=(0.5, 1.0),
                    fontsize=9, framealpha=0.85, ncol=1, borderpad=0.6)
    leg.get_frame().set_edgecolor("0.4")

    out = os.path.join(IMG_DIR, "klt_tracking_walking1.png")
    fig.subplots_adjust(left=0, right=1, top=1, bottom=0)
    fig.savefig(out, dpi=200, bbox_inches="tight", pad_inches=0.02)
    plt.close(fig)
    print(f"[fig1] KLT 跟踪图: frame={s}->{s+_GAP}  inliers={len(gi)} rejected={len(ri)}  -> {out}")
    return out


# ----------------------------------------------------------------------------
# Figures 2 & 3: 轨迹对比图（高斯 / L1）
# ----------------------------------------------------------------------------
def _estimate_raw_trajectory():
    """复用工程的运动估计 + 平滑，返回 raw / gauss / l1 轨迹（已做 GT 符号对齐）。"""
    from motion_estimation import estimate_motion
    transforms, _ = estimate_motion(SYNTH_VID, proc_scale=0.5)
    n = len(transforms)
    _, dg = smooth_trajectory(transforms, method="gaussian", radius=30)
    _, dl = smooth_trajectory(transforms, method="l1")
    raw = dg["raw_trajectory"]; sm_g = dg["smoothed_trajectory"]; sm_l = dl["smoothed_trajectory"]

    m = sio.loadmat(SYNTH_GT)
    gx = m["Tx"].ravel(); gy = m["Ty"].ravel()
    L = min(n, gx.size)
    # 与 run_paper_experiments 一致：若估计与 GT 反相关则翻转符号对齐
    if np.corrcoef(raw[:L, 0], gx[:L])[0, 1] < 0:
        raw = raw.copy(); raw[:, :2] *= -1
        sm_g = sm_g.copy(); sm_g[:, :2] *= -1
        sm_l = sm_l.copy(); sm_l[:, :2] *= -1
    return L, raw, sm_g, sm_l, gx[:L], gy[:L]


def _plot_traj(out_name, title, raw, sm, gx, gy, L):
    t = np.arange(L)
    fig, ax = plt.subplots(1, 2, figsize=(11, 4.2))
    for k, (e, s, g, lab) in enumerate([(raw[:L, 0], sm[:L, 0], gx, "X"),
                                        (raw[:L, 1], sm[:L, 1], gy, "Y")]):
        ax[k].plot(t, e, color="#d62728", lw=1.0, alpha=0.9, label="Estimated (raw)")
        ax[k].plot(t, s, color="#1f77b4", lw=1.9, label="Smoothed")
        ax[k].plot(t, g, color="#2ca02c", lw=1.4, ls="--", label="Ground Truth")
        ax[k].set_xlabel("Frame"); ax[k].set_ylabel(f"{lab} translation (px)")
        ax[k].grid(alpha=0.3); ax[k].legend(fontsize=8)
    fig.suptitle(title, fontsize=12)
    fig.tight_layout()
    out = os.path.join(IMG_DIR, out_name)
    fig.savefig(out, dpi=130); plt.close(fig)
    print(f"[traj] {title}  -> {out}")
    return out


def make_trajectory_figures():
    L, raw, sm_g, sm_l, gx, gy = _estimate_raw_trajectory()
    _plot_traj("synth_handheld_walking_trajectory_gauss.png",
               "Handheld Walking  —  Gaussian smoothing", raw, sm_g, gx, gy, L)
    _plot_traj("synth_handheld_walking_trajectory_l1.png",
               "Handheld Walking  —  L1 optimal path", raw, sm_l, gx, gy, L)


if __name__ == "__main__":
    os.makedirs(IMG_DIR, exist_ok=True)
    make_klt_figure()
    make_trajectory_figures()
    print("\n完成。三张图已写入", IMG_DIR)
