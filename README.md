# 视频运动防抖与画面去模糊

> 基于 MATLAB 的三阶段模块化视频防抖去模糊系统  
> 参考论文：17 篇（2017–2026），核心引用 LightStab (CVPR 2026) + 中北大学在线拼接防抖 (MDPI 2025)

## 项目文件结构

```
结课作业/
├── src/
│   ├── init_project.m              ← 首次运行：添加路径、检查工具箱
│   ├── main_pipeline.m             ← 主流水线入口
│   │
│   ├── motion_estimation/          ← [模块一] 运动估计（角色二+三）
│   │   ├── detect_keypoints.m      # 多检测器协作（SIFT+SURF）
│   │   ├── match_keypoints.m       # 特征匹配 + Lowe's ratio test
│   │   ├── compute_optical_flow.m  # 因果稠密光流
│   │   ├── fuse_motion_field.m     # 稀疏关键点引导光流融合
│   │   ├── estimate_global_transform.m  # RANSAC 仿射/投影拟合
│   │   └── run_motion_estimation.m # 模块一主入口
│   │
│   ├── motion_smoothing/           ← [模块二] 运动分解与平滑（角色四+五）
│   │   ├── decompose_affine_params.m    # 6自由度仿射参数提取
│   │   ├── relative_coordinate_model.m  # 相对坐标建模 + 逆变换
│   │   ├── markov_window_smooth.m       # 马尔可夫窗口约束平滑
│   │   ├── gaussian_smooth.m            # 基线高斯平滑
│   │   └── run_motion_smoothing.m       # 模块二主入口
│   │
│   ├── frame_synthesis/            ← [模块三] 帧合成与去模糊（角色六）
│   │   ├── warp_frame.m            # 仿射 warp + 边界处理
│   │   ├── estimate_blur_kernel.m  # 模糊核估计（从运动参数）
│   │   ├── wiener_deblur.m         # 频域维纳去卷积
│   │   └── run_frame_synthesis.m   # 模块三主入口
│   │
│   ├── evaluation/                 ← 测试与评估（角色八）
│   │   ├── compute_psnr_ssim.m     # 帧间 PSNR / SSIM
│   │   ├── compute_stabilization_ratio.m  # 稳定比 SR
│   │   ├── visualize_trajectory.m  # 运动轨迹可视化
│   │   ├── visualize_frame_comparison.m   # 帧对比图
│   │   └── run_ablation_study.m    # 消融实验自动化
│   │
│   ├── app/                        ← App Designer GUI（角色七）
│   │   ├── stabilization_gui.mlapp # 主界面（可交互桌面应用）
│   │   ├── phase_worker.m          # parfeval 后台处理 Worker
│   │   └── trajectory_viewer.m     # 轨迹可视化子窗口
│   │
│   └── utils/                      ← 工具函数
│       ├── load_video.m            # 视频加载
│       ├── save_video.m            # 视频保存
│       └── timer_utils.m           # 嵌套计时器类
│
├── data/
│   ├── test_videos/   ← 测试素材（.gitkeep 保留目录结构）
│   └── results/       ← 输出视频 + 诊断 .mat + 消融 .csv
│
├── papers/            ← 论文 PDF + 中文总结（17 篇）
├── docs/              ← 结课报告等文档
├── 工作计划_视频防抖去模糊_8人团队.md
└── 视频运动防抖与画面去模糊.md   ← 课题要求原文
```

## 快速开始

```matlab
% 1. 初始化项目路径
cd('src');
init_project();

% 2. 确认测试视频已放入 data/test_videos/

% 3a. 命令行运行完整流水线
main_pipeline(struct('inputVideo', 'data/test_videos/your_video.mp4'));

% 3b. 或启动 App Designer 图形界面
cd('app');
stabilization_gui;

% 4. 运行消融实验（多种参数组合自动对比）
run_ablation_study('data/test_videos/your_video.mp4');
```

## GUI 功能说明

启动 `stabilization_gui` 后：

| 功能 | 操作 |
|------|------|
| 加载视频 | 点击「加载视频」选择 .mp4/.avi 文件 |
| 预览原始帧 | 左侧 UIAxes + 底部滑块拖动跳帧 |
| 开始处理 | 点击「开始处理」触发三阶段流水线（parfeval 异步） |
| 暂停/恢复 | 点击「暂停」暂停 Worker，再次点击恢复 |
| 实时指标 | PSNR / SSIM / 帧率 / 延迟实时更新 |
| 轨迹分析 | 处理中点击「轨迹分析」弹出运动轨迹子窗口 |
| 导出结果 | 处理完成后点击「导出结果」保存 .mp4 |

处理架构：**阶段一**（运动估计扫描）→ **阶段二**（批量平滑）→ **阶段三**（帧合成预览），parfeval 后台执行不阻塞 UI。

## 三阶段流水线架构

```
输入不稳定视频
  │
  ▼
[模块一] 运动估计 ──▶ 输出: 3×3×N 变换矩阵序列
  │  参考: LightStab (CVPR 2026)
  │  SIFT+SURF → RANSAC 仿射拟合
  │
  ▼
[模块二] 运动分解与平滑 ──▶ 输出: 平滑后变换矩阵序列
  │  参考: 中北大学 MDPI 2025
  │  仿射分解 → 相对坐标建模 → 马尔可夫窗口平滑
  │
  ▼
[模块三] 帧合成与去模糊 ──▶ 输出: 稳定清晰帧
  │  参考: 门控注意力 CVPR 2021 + CompEvent 频域
  │  仿射 warp → 边界反射填充 → 维纳去卷积
  │
  ▼
输出稳定视频 + 评估报告
```

## 角色分工速查

| 角色 | 负责模块 | 核心文件 |
|------|---------|---------|
| 项目负责人 | 架构 + 报告 | `main_pipeline.m` |
| 角色二 | 关键点检测与匹配 | `detect_keypoints.m` `match_keypoints.m` `estimate_global_transform.m` |
| 角色三 | 光流与运动场融合 | `compute_optical_flow.m` `fuse_motion_field.m` |
| 角色四 | 仿射分解与运动分离 | `decompose_affine_params.m` `gaussian_smooth.m` |
| 角色五 | 相对坐标马尔可夫平滑 | `relative_coordinate_model.m` `markov_window_smooth.m` |
| 角色六 | 帧合成与去模糊 | `warp_frame.m` `estimate_blur_kernel.m` `wiener_deblur.m` |
| 角色七 | MATLAB App Designer GUI | `stabilization_gui.mlapp` `phase_worker.m` `trajectory_viewer.m` |
| 角色八 | 测试评估 | `evaluation/*.m` |

## 依赖的 MATLAB 工具箱

- **Computer Vision Toolbox** — SIFT/SURF 检测器、光流、RANSAC、VideoReader/Writer
- **Image Processing Toolbox** — imwarp、deconvwnr、fspecial、imcrop
- **Parallel Computing Toolbox** — parfeval 异步处理（可选，加速用）
- **Deep Learning Toolbox** — importONNXNetwork（可选，去模糊网络）

## 参考文献速览

最核心引用的三篇论文：

- **LightStab (CVPR 2026)**: 无监督在线防抖，多检测器协作 + 因果光流融合。有开源代码。
- **中北大学在线拼接防抖 (MDPI Applied Sciences, 2025)**: 相对坐标马尔可夫平滑 + 动态注意力掩码。有开源代码。
- **门控时空注意力去模糊 (CVPR 2021)**: 选择性计算、多尺度注意力。去模糊子模块核心参考。

完整 17 篇论文清单与引用规划见 `papers/00_技术选型_从17篇论文到可实施方案.md`。
