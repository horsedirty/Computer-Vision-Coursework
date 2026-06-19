# 视频运动防抖与画面去模糊

基于传统计算机视觉的视频防抖项目（**不使用深度学习**）。核心算法已从 MATLAB
重构为 **Python + OpenCV**，以提升运行效率（评分含运行时间 40%）。

## 算法实现

完整流水线与用法见 [`stabilizer/`](stabilizer/README.md)：

- `stabilizer/motion_estimation.py` — KLT 光流 + 相似变换(RANSAC)运动估计（降采样提速）
- `stabilizer/smoothing.py` — 累积轨迹 + 高斯/L1 平滑，分离主动运动与抖动
- `stabilizer/synthesis.py` — warp 重排 + 去黑边 + 锐化 + 编码
- `stabilizer/metrics.py` — 有效防抖时长占比评测

```bash
cd stabilizer
python3 -m venv ../.venv && ../.venv/bin/pip install -r requirements.txt
../.venv/bin/python stabilize.py input.mp4 -o output.mp4 --eval
```

## 数据与参考

- `data/test_videos/` — 测试视频与 ground truth
- `papers/` — 参考文献（17 篇）
- `docs/` — 报告与 PPT
