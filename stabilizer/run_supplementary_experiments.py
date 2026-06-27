"""补充实验：为论文 3.4/3.5/3.6.2 生成 (1) 参数敏感性(降采样比例 rho、FB阈值 eps)，
(2) 去掉前向-后向校验的消融，(3) 未防抖基线 vs 本文 的对比。
所有 RMSE 与主实验 run_paper_experiments.py 口径一致(对 GT 做符号对齐)。
结果打印为可直接粘贴论文的 Markdown 表，并写入 supp_results.json。
"""
from __future__ import annotations
import json, os, copy
import numpy as np
import scipy.io as sio

import motion_estimation
from motion_estimation import estimate_motion
from smoothing import smooth_trajectory
from metrics import stabilization_ratio

VID_DIR = "../data/test_videos/analog_data"
CASES = [
    ("synth_quick_panning",    "画面剧烈抖动"),
    ("synth_handheld_walking", "手持步行"),
    ("synth_static_standing",  "静止站立"),
    ("synth_bumpy_riding",     "骑行颠簸"),
]


def gt_abs_traj(matpath, n):
    m = sio.loadmat(matpath)
    Tx, Ty, Th = m["Tx"].ravel(), m["Ty"].ravel(), m["Theta"].ravel()
    ng = min(n, Tx.size)
    return Tx[:ng], Ty[:ng], Th[:ng], ng


def run_one(name, proc_scale, fb_thresh):
    """跑一次运动估计，返回 RMSE/内点率/耗时/回退帧数。"""
    vid = os.path.join(VID_DIR, f"{name}.mp4")
    mat = os.path.join(VID_DIR, f"{name}_groundtruth.mat")
    old = motion_estimation._FB_THRESH
    motion_estimation._FB_THRESH = fb_thresh
    try:
        transforms, diag = estimate_motion(vid, proc_scale=proc_scale)
    finally:
        motion_estimation._FB_THRESH = old
    n = len(transforms)
    _, dg = smooth_trajectory(transforms, method="gaussian", radius=30)
    raw = dg["raw_trajectory"]
    gx, gy, _, ng = gt_abs_traj(mat, n)
    L = min(n, ng)
    ex, ey = raw[:L, 0].copy(), raw[:L, 1].copy()
    if np.corrcoef(ex, gx[:L])[0, 1] < 0:
        ex, ey = -ex, -ey
    rmse_x = float(np.sqrt(np.mean((ex - gx[:L]) ** 2)))
    rmse_y = float(np.sqrt(np.mean((ey - gy[:L]) ** 2)))
    rmse_t = float(np.sqrt(rmse_x ** 2 + rmse_y ** 2))
    inlier = float(np.mean(diag.inlier_ratios)) if diag.inlier_ratios else 0.0
    return dict(rmse_x=rmse_x, rmse_y=rmse_y, rmse_t=rmse_t, inlier=inlier,
                ms=diag.avg_time_per_frame_ms, fallback=len(diag.fallback_frames), n=n)


def fmt(rows, header):
    line = "| " + " | ".join(header) + " |"
    sep = "|" + "|".join([":---:"] * len(header)) + "|"
    body = "\n".join("| " + " | ".join(str(c) for c in r) + " |" for r in rows)
    return "\n".join([line, sep, body])


def main():
    out = {"ablation_fb": [], "sweep_rho": [], "sweep_eps": [], "baseline": []}

    # ---------- 消融: 完整 vs 去掉FB校验 (rho=0.5) ----------
    print("\n########## 消融实验：前向-后向(FB)校验 ##########")
    abl_rows = []
    for name, cn in CASES:
        full = run_one(name, 0.5, 3.0)
        nofb = run_one(name, 0.5, float("inf"))
        out["ablation_fb"].append(dict(name=name, cn=cn, full=full, nofb=nofb))
        abl_rows.append([cn, f"{full['rmse_t']:.2f}", f"{full['inlier']:.3f}",
                         f"{nofb['rmse_t']:.2f}", f"{nofb['inlier']:.3f}"])
        print(f"  {cn}: full RMSE={full['rmse_t']:.2f} inlier={full['inlier']:.3f} | "
              f"noFB RMSE={nofb['rmse_t']:.2f} inlier={nofb['inlier']:.3f}")
    abl_md = fmt(abl_rows, ["测试场景", "完整 RMSE/px", "完整内点率",
                            "去FB校验 RMSE/px", "去FB校验内点率"])

    # ---------- 参数: 降采样比例 rho ----------
    print("\n########## 参数敏感性：降采样比例 rho ##########")
    rho_rows = []
    for rho in (0.25, 0.5, 1.0):
        rt, ms, inl = [], [], []
        for name, cn in CASES:
            r = run_one(name, rho, 3.0)
            rt.append(r["rmse_t"]); ms.append(r["ms"]); inl.append(r["inlier"])
            out["sweep_rho"].append(dict(rho=rho, name=name, **r))
        rho_rows.append([rho, f"{np.mean(rt):.2f}", f"{np.mean(ms):.1f}", f"{np.mean(inl):.3f}"])
        print(f"  rho={rho}: meanRMSE={np.mean(rt):.2f} meanMs={np.mean(ms):.1f} meanInlier={np.mean(inl):.3f}")
    rho_md = fmt(rho_rows, ["降采样比例 ρ", "平均总RMSE/px", "平均耗时(ms/帧)", "平均内点率"])

    # ---------- 参数: FB阈值 eps ----------
    print("\n########## 参数敏感性：FB阈值 eps ##########")
    eps_rows = []
    for eps in (1.0, 3.0, 5.0):
        rt, inl = [], []
        for name, cn in CASES:
            r = run_one(name, 0.5, eps)
            rt.append(r["rmse_t"]); inl.append(r["inlier"])
            out["sweep_eps"].append(dict(eps=eps, name=name, **r))
        eps_rows.append([eps, f"{np.mean(rt):.2f}", f"{np.mean(inl):.3f}"])
        print(f"  eps={eps}: meanRMSE={np.mean(rt):.2f} meanInlier={np.mean(inl):.3f}")
    eps_md = fmt(eps_rows, ["FB阈值 ε/px", "平均总RMSE/px", "平均内点率"])

    # ---------- 基线: 未防抖 vs 本文(读主实验结果) ----------
    print("\n########## 基线对比：未防抖 vs 本文 ##########")
    base_md = ""
    if os.path.exists("paper_results.json"):
        pr = {r["name"]: r for r in json.load(open("paper_results.json"))}
        base_rows = []
        for name, cn in CASES:
            r = pr.get(name)
            if not r:
                continue
            out["baseline"].append(dict(name=name, cn=cn,
                ratio_before=r["ratio_before"], ratio_g=r["ratio_g"], ratio_l=r["ratio_l"],
                jit_before=r["jit_before"], jit_g=r["jit_g"]))
            base_rows.append([cn,
                f"{r['ratio_before']*100:.1f}", f"{r['ratio_g']*100:.1f}", f"{r['ratio_l']*100:.1f}",
                f"{r['jit_before']:.2f}", f"{r['jit_g']:.2f}"])
        base_md = fmt(base_rows, ["测试场景", "未防抖占比/%", "本文(高斯)/%", "本文(L1)/%",
                                  "未防抖抖动/px", "本文(高斯)抖动/px"])

    json.dump(out, open("supp_results.json", "w"), ensure_ascii=False, indent=2)

    print("\n\n==================== 可直接粘贴论文的 Markdown 表 ====================\n")
    print("### 表 基线对比：未防抖 vs 本文\n");  print(base_md, "\n")
    print("### 表 前向-后向校验消融（ρ=0.5）\n"); print(abl_md, "\n")
    print("### 表 降采样比例 ρ 敏感性（4场景平均）\n"); print(rho_md, "\n")
    print("### 表 FB阈值 ε 敏感性（4场景平均）\n"); print(eps_md, "\n")
    print(">>> 明细已写入 supp_results.json")


if __name__ == "__main__":
    main()
