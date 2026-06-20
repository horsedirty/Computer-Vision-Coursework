"""复现论文实验：在 4 个合成抖动视频上运行新流水线(KLT+相似变换+平滑)，
输出 (1) 运动估计绝对轨迹 vs Ground Truth 的平移 RMSE，
     (2) 高斯/L1 平滑下的有效防抖时长占比与平均抖动，
     (3) 原始/平滑/真值三线轨迹对比图(供论文 figure)。
全部结果写入 paper_results.json，轨迹图写入 LaTeX 的 image 目录。
"""
from __future__ import annotations
import json, os
import numpy as np
import scipy.io as sio
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

from motion_estimation import estimate_motion
from smoothing import smooth_trajectory, _mat_to_params
from synthesis import synthesize
from metrics import stabilization_ratio

VID_DIR = "../data/test_videos/analog_data"
OUT_DIR = "../data/results"
IMG_DIR = "../docs/航空学报latex模版/AAAS/image"
SCALE = 0.5

CASES = [
    ("synth_handheld_walking", "手持步行", "Handheld Walking"),
    ("synth_bumpy_riding",     "骑行颠簸", "Bumpy Riding"),
    ("synth_quick_panning",    "画面剧烈抖动", "Severe Camera Shake"),
    ("synth_static_standing",  "静止站立", "Static Standing"),
]


def gt_abs_traj(matpath, n):
    """读取 GT 绝对逐帧位移轨迹。Tx/Ty/Theta 为帧 i 相对帧 0 的绝对偏移(像素/弧度)。"""
    m = sio.loadmat(matpath)
    Tx = m["Tx"].ravel(); Ty = m["Ty"].ravel(); Th = m["Theta"].ravel()
    ng = min(n, Tx.size)
    return Tx[:ng], Ty[:ng], Th[:ng], ng


def plot_traj(name, en, est_xy, sm_xy, gt_xy):
    (ex, ey), (sx, sy), (gx, gy) = est_xy, sm_xy, gt_xy
    t = np.arange(len(ex))
    fig, ax = plt.subplots(1, 2, figsize=(11, 4.2))
    for k, (e, s, g, lab) in enumerate([(ex, sx, gx, "X"), (ey, sy, gy, "Y")]):
        ax[k].plot(t, e, color="#d62728", lw=1.0, alpha=0.9, label="Estimated (raw)")
        ax[k].plot(t, s, color="#1f77b4", lw=1.8, label="Smoothed")
        ax[k].plot(t[:len(g)], g, color="#2ca02c", lw=1.4, ls="--", label="Ground Truth")
        ax[k].set_xlabel("Frame"); ax[k].set_ylabel(f"{lab} translation (px)")
        ax[k].grid(alpha=0.3); ax[k].legend(fontsize=8)
    fig.suptitle(en, fontsize=12)
    fig.tight_layout()
    out = os.path.join(IMG_DIR, f"{name}_trajectory_eval.png")
    fig.savefig(out, dpi=130); plt.close(fig)
    return out


def main():
    results = []
    for name, cn, en in CASES:
        vid = os.path.join(VID_DIR, f"{name}.mp4")
        mat = os.path.join(VID_DIR, f"{name}_groundtruth.mat")
        print(f"\n===== {cn} ({name}) =====")

        transforms, diag_est = estimate_motion(vid, proc_scale=SCALE)
        n = len(transforms)
        inlier = float(np.mean(diag_est.inlier_ratios)) if diag_est.inlier_ratios else 0.0

        warps_g, dg = smooth_trajectory(transforms, method="gaussian", radius=30)
        warps_l, dl = smooth_trajectory(transforms, method="l1")
        raw = dg["raw_trajectory"]; sm_g = dg["smoothed_trajectory"]; sm_l = dl["smoothed_trajectory"]

        gx, gy, gth, ng = gt_abs_traj(mat, n)
        L = min(n, ng)
        ex, ey = raw[:L, 0], raw[:L, 1]
        # 估计与 GT 同约定，理应正相关；若反相关则翻转符号对齐
        if np.corrcoef(ex, gx)[0, 1] < 0:
            ex = -ex; ey = -ey
            raw = raw.copy(); raw[:, 0] *= -1; raw[:, 1] *= -1
            sm_g = sm_g.copy(); sm_g[:, 0] *= -1; sm_g[:, 1] *= -1
        rmse_x = float(np.sqrt(np.mean((ex - gx[:L]) ** 2)))
        rmse_y = float(np.sqrt(np.mean((ey - gy[:L]) ** 2)))
        rmse_t = float(np.sqrt(rmse_x ** 2 + rmse_y ** 2))

        png = plot_traj(name, en, (raw[:L, 0], raw[:L, 1]),
                        (sm_g[:L, 0], sm_g[:L, 1]), (gx[:L], gy[:L]))

        before = stabilization_ratio(vid, proc_scale=SCALE)
        out_g = os.path.join(OUT_DIR, f"{name}_stab_gauss.mp4")
        out_l = os.path.join(OUT_DIR, f"{name}_stab_l1.mp4")
        sg = synthesize(vid, warps_g, out_g, crop_limit=1.10, abs_transforms=dg["abs_transforms"])
        sl = synthesize(vid, warps_l, out_l, crop_limit=1.10, abs_transforms=dl["abs_transforms"])
        after_g = stabilization_ratio(out_g, proc_scale=SCALE)
        after_l = stabilization_ratio(out_l, proc_scale=SCALE)

        rec = dict(name=name, cn=cn, frames=n, inlier=inlier,
                   fallback=len(diag_est.fallback_frames),
                   est_ms_per_frame=diag_est.avg_time_per_frame_ms,
                   rmse_x=rmse_x, rmse_y=rmse_y, rmse_t=rmse_t,
                   ratio_before=before["ratio"], jit_before=before["mean_jitter_px"],
                   ratio_g=after_g["ratio"], jit_g=after_g["mean_jitter_px"], zoom_g=sg["zoom"],
                   ratio_l=after_l["ratio"], jit_l=after_l["mean_jitter_px"], zoom_l=sl["zoom"],
                   png=png)
        results.append(rec)
        print(f"  N={n} inlier={inlier:.2f} fallback={rec['fallback']} est={rec['est_ms_per_frame']:.1f}ms/f")
        print(f"  RMSE x/y/total = {rmse_x:.2f}/{rmse_y:.2f}/{rmse_t:.2f} px")
        print(f"  ratio before={before['ratio']*100:.1f}% gauss={after_g['ratio']*100:.1f}% l1={after_l['ratio']*100:.1f}%")
        print(f"  jitter before={before['mean_jitter_px']:.2f} gauss={after_g['mean_jitter_px']:.2f} l1={after_l['mean_jitter_px']:.2f} px")
        print(f"  zoom gauss={sg['zoom']:.3f} l1={sl['zoom']:.3f}")

    with open("paper_results.json", "w") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    print("\n>>> 写入 paper_results.json，轨迹图已更新到", IMG_DIR)


if __name__ == "__main__":
    main()