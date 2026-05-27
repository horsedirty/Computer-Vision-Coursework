# 视频稳定综合评估报告

生成时间: 26-May-2026 15:56:10

输入视频: `data/test_videos/test1.mp4`

## 消融实验结果

| Experiment | PSNR (dB) | SSIM | SR | MotionEst (ms) | Smoothing (ms) | Synthesis (ms) |
|----------|-----------|------|-----|---------------|-----------|-------------|
| 基线_SIFT_高斯_无去模糊 | NaN | NaN | NaN | 0.00 | 0.00 | 0.00 |
| 双检测器_SIFT+SURF_高斯_无去模糊 | NaN | NaN | NaN | 0.00 | 0.00 | 0.00 |
| SIFT_相对坐标高斯_无去模糊 | NaN | NaN | NaN | 0.00 | 0.00 | 0.00 |
| SIFT_马尔可夫_l=3_无去模糊 | NaN | NaN | NaN | 0.00 | 0.00 | 0.00 |
| SIFT_马尔可夫_l=3_维纳去模糊 | NaN | NaN | NaN | 0.00 | 0.00 | 0.00 |
| SIFT_马尔可夫_l=1_无去模糊 | NaN | NaN | NaN | 0.00 | 0.00 | 0.00 |
| SIFT_马尔可夫_l=5_无去模糊 | NaN | NaN | NaN | 0.00 | 0.00 | 0.00 |

![消融实验柱状图](ablation/ablation_bars.png)

### 各模块耗时分布

- 基线_SIFT_高斯_无去模糊: ![Pie](ablation/pie_基线_SIFT_高斯_无去模糊.png)
- 双检测器_SIFT+SURF_高斯_无去模糊: ![Pie](ablation/pie_双检测器_SIFT+SURF_高斯_无去模糊.png)
- SIFT_相对坐标高斯_无去模糊: ![Pie](ablation/pie_SIFT_相对坐标高斯_无去模糊.png)
- SIFT_马尔可夫_l=3_无去模糊: ![Pie](ablation/pie_SIFT_马尔可夫_l=3_无去模糊.png)
- SIFT_马尔可夫_l=3_维纳去模糊: ![Pie](ablation/pie_SIFT_马尔可夫_l=3_维纳去模糊.png)
- SIFT_马尔可夫_l=1_无去模糊: ![Pie](ablation/pie_SIFT_马尔可夫_l=1_无去模糊.png)
- SIFT_马尔可夫_l=5_无去模糊: ![Pie](ablation/pie_SIFT_马尔可夫_l=5_无去模糊.png)

