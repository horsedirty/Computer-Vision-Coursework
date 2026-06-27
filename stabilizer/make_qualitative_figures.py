"""定性实验图：从原始抖动视频与稳定后视频中抽取同帧，做"防抖前后画面对比"蒙太奇。
每场景生成一张 2 行(上=原始抖动, 下=本文稳定) × 3 列(不同时刻) 的对比图，
叠加固定十字参考线：原始画面内容相对参考线明显漂移/旋转，稳定后基本锁定。
输出到 ../docs/航空学报latex模版/AAAS/image/ 供论文引用。
"""
from __future__ import annotations
import os
import cv2
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager

# 中文字体（macOS 常见）
for fp in ["/System/Library/Fonts/PingFang.ttc", "/System/Library/Fonts/STHeiti Medium.ttc",
           "/System/Library/Fonts/Hiragino Sans GB.ttc"]:
    if os.path.exists(fp):
        font_manager.fontManager.addfont(fp)
        plt.rcParams["font.family"] = font_manager.FontProperties(fname=fp).get_name()
        break
plt.rcParams["axes.unicode_minus"] = False

ORIG_DIR = "../data/test_videos/analog_data"
STAB_DIR = "../data/results"
IMG_DIR = "../docs/航空学报latex模版/AAAS/image"
FRAMES = [60, 160, 260]

CASES = [
    ("synth_handheld_walking", "手持步行 Handheld Walking"),
    ("synth_quick_panning",    "画面剧烈抖动 Severe Camera Shake"),
    ("synth_static_standing",  "静止站立 Static Standing"),
    ("synth_bumpy_riding",     "骑行颠簸 Bumpy Riding"),
]


def read_frames(path, idxs):
    cap = cv2.VideoCapture(path)
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    out = []
    for i in idxs:
        j = min(i, total - 1)
        cap.set(cv2.CAP_PROP_POS_FRAMES, j)
        ok, fr = cap.read()
        out.append(cv2.cvtColor(fr, cv2.COLOR_BGR2RGB) if ok else None)
    cap.release()
    return out


def draw_ref(ax, img):
    h, w = img.shape[:2]
    ax.imshow(img)
    ax.axvline(w / 2, color="yellow", lw=0.8, alpha=0.7)
    ax.axhline(h / 2, color="yellow", lw=0.8, alpha=0.7)
    ax.set_xticks([]); ax.set_yticks([])


def main():
    os.makedirs(IMG_DIR, exist_ok=True)
    for name, title in CASES:
        orig = os.path.join(ORIG_DIR, f"{name}.mp4")
        stab = os.path.join(STAB_DIR, f"{name}_stab_gauss.mp4")
        if not (os.path.exists(orig) and os.path.exists(stab)):
            print("skip (missing):", name); continue
        of = read_frames(orig, FRAMES)
        sf = read_frames(stab, FRAMES)
        ncol = len(FRAMES)
        fig, ax = plt.subplots(2, ncol, figsize=(3.0 * ncol, 4.0))
        for c in range(ncol):
            if of[c] is not None: draw_ref(ax[0, c], of[c])
            if sf[c] is not None: draw_ref(ax[1, c], sf[c])
            ax[0, c].set_title(f"t = {FRAMES[c]}", fontsize=10)
        ax[0, 0].set_ylabel("原始抖动\nOriginal", fontsize=11)
        ax[1, 0].set_ylabel("本文稳定\nStabilized", fontsize=11)
        # set_ylabel needs visible axis; re-enable just the label
        for a, lab in [(ax[0, 0], "原始抖动 / Original"), (ax[1, 0], "本文稳定 / Stabilized")]:
            a.set_yticks([]); a.set_ylabel(lab, fontsize=11)
        fig.suptitle(f"防抖前后画面对比（黄线为固定参考十字）— {title}", fontsize=12)
        fig.tight_layout(rect=[0, 0, 1, 0.96])
        out = os.path.join(IMG_DIR, f"{name}_qualitative.png")
        fig.savefig(out, dpi=140); plt.close(fig)
        print("wrote", out)


if __name__ == "__main__":
    main()
