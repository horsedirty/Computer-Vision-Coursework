"""视频防抖主入口(命令行)。

三阶段流水线：运动估计(KLT+相似变换) -> 运动平滑(高斯/L1) -> 帧合成(warp+裁剪+锐化)。
评分相关：处理后自动计算 有效防抖时长占比，并打印各阶段耗时(对应运行时间 40% 项)。

用法:
    python stabilize.py input.mp4 -o output.mp4
    python stabilize.py input.mp4 -o out.mp4 --smooth l1 --proc-scale 0.5 --eval
"""

from __future__ import annotations

import argparse
import os
import sys
import time

from motion_estimation import estimate_motion
from smoothing import smooth_trajectory
from synthesis import synthesize


def _bar(prefix):
    def cb(i, n):
        if n and (i % 10 == 0 or i == n - 1):
            pct = 100.0 * (i + 1) / n
            sys.stdout.write(f"\r  {prefix}: {i + 1}/{n} ({pct:5.1f}%)")
            sys.stdout.flush()
            if i >= n - 1:
                sys.stdout.write("\n")
    return cb


def run(input_path, output_path, smooth="gaussian", radius=30,
        proc_scale=0.5, zoom=None, crop_limit=1.10, sharpen=True,
        do_eval=False, compare=False):
    print(f"=== 视频防抖流水线 ===\n输入: {input_path}")
    t_all = time.perf_counter()

    print("阶段一：运动估计 (KLT + 相似变换 RANSAC)...")
    transforms, diag_est = estimate_motion(input_path, proc_scale=proc_scale,
                                           progress=_bar("estimate"))
    print(f"  耗时 {diag_est.total_time_ms:.0f} ms "
          f"(每帧 {diag_est.avg_time_per_frame_ms:.1f} ms), "
          f"回退帧 {len(diag_est.fallback_frames)}, "
          f"平均内点率 {sum(diag_est.inlier_ratios)/max(1,len(diag_est.inlier_ratios)):.2f}")

    print(f"阶段二：运动平滑 ({smooth})...")
    t1 = time.perf_counter()
    smoothed, _ = smooth_trajectory(transforms, method=smooth, radius=radius)
    print(f"  耗时 {(time.perf_counter()-t1)*1000:.0f} ms")

    compare_path = None
    if compare:
        root, ext = os.path.splitext(output_path)
        compare_path = f"{root}_compare{ext}"

    print("阶段三：帧合成与导出...")
    diag_syn = synthesize(input_path, smoothed, output_path,
                          zoom=zoom, crop_limit=crop_limit, sharpen=sharpen,
                          compare_path=compare_path, progress=_bar("synthesize"))
    print(f"  耗时 {diag_syn['total_time_ms']:.0f} ms, "
          f"自适应放大 {diag_syn['zoom']:.3f}x (裁掉边缘 {(1-1/diag_syn['zoom'])*50:.1f}%)")

    total_ms = (time.perf_counter() - t_all) * 1000
    print(f"=== 完成，总耗时 {total_ms:.0f} ms ===\n输出: {output_path}")
    if compare_path:
        print(f"对比视频: {compare_path}")

    if do_eval:
        from metrics import stabilization_ratio
        print("评测：计算有效防抖时长占比...")
        before = stabilization_ratio(input_path, proc_scale=proc_scale)
        after = stabilization_ratio(output_path, proc_scale=proc_scale)
        print(f"  处理前: {before['ratio']*100:.1f}%  (平均抖动 {before['mean_jitter_px']:.2f}px)")
        print(f"  处理后: {after['ratio']*100:.1f}%  (平均抖动 {after['mean_jitter_px']:.2f}px)")
    return total_ms


def main():
    ap = argparse.ArgumentParser(description="基于 OpenCV 的传统视频防抖")
    ap.add_argument("input")
    ap.add_argument("-o", "--output", required=True)
    ap.add_argument("--smooth", choices=["gaussian", "l1"], default="gaussian")
    ap.add_argument("--radius", type=int, default=30, help="高斯平滑半径(帧)")
    ap.add_argument("--proc-scale", type=float, default=0.5, help="运动估计处理分辨率比例")
    ap.add_argument("--zoom", type=float, default=None, help="固定放大倍数(默认自适应，不超过 crop-limit)")
    ap.add_argument("--crop-limit", type=float, default=1.10,
                    help="裁剪预算/最大放大倍数，越小越贴近原画(默认1.10≈每边4.5%%)")
    ap.add_argument("--no-sharpen", action="store_true")
    ap.add_argument("--eval", action="store_true", help="处理后计算有效防抖时长占比")
    ap.add_argument("--compare", action="store_true", help="额外输出 [原始|去抖] 并排对比视频")
    args = ap.parse_args()
    run(args.input, args.output, smooth=args.smooth, radius=args.radius,
        proc_scale=args.proc_scale, zoom=args.zoom, crop_limit=args.crop_limit,
        sharpen=not args.no_sharpen, do_eval=args.eval, compare=args.compare)


if __name__ == "__main__":
    main()
