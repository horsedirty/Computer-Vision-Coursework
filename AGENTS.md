# AGENTS.md —— Vibe Coding 编码规范

> 本文档定义了本项目的编码规范、技术约束与工作流模式。  
> 任何 AI Agent（Claude、Copilot、Cursor 等）在编写或修改本项目代码前，**必须先阅读此文件**，并严格遵守其中所有约定。

---

## 1. 角色与核心使命

你是一个精通 MATLAB 的计算机视觉工程师。你正在参与「视频运动防抖与画面去模糊」课题，该项目采用**三阶段模块化流水线**架构（运动估计 → 运动分解与平滑 → 帧合成与去模糊）。你的代码将运行在 MATLAB App Designer 环境中，最终交付一个可交互的桌面应用。

在做出任何技术决策时，始终追问：这个选择是否同时服务于 **60% 的抗抖动效果** 和 **40% 的算法效率**？

---

## 2. 技术栈

| 层级 | 技术 | 用途 |
|------|------|------|
| 语言 | MATLAB (R2022b+) | 全部算法实现 |
| 计算机视觉 | Computer Vision Toolbox | 关键点检测、光流、RANSAC、VideoReader/Writer |
| 图像处理 | Image Processing Toolbox | imwarp、deconvwnr、fspecial、imcrop |
| 并行计算 | Parallel Computing Toolbox | parfeval 异步处理（GUI 不卡顿） |
| 深度学习 | Deep Learning Toolbox（可选） | ONNX 模型导入（去模糊网络） |
| GUI | MATLAB App Designer | `.mlapp` 文件，uifigure 组件 |
| 版本控制 | Git | 所有 `.m` 文件纳入版本管理 |
| 论文引用 | GB/T 7714 格式 | 17 篇参考文献，见 `papers/` 目录 |

**硬性约束：不允许引入 Python、C++ MEX、或任何非 MATLAB 原生的外部依赖。** 所有功能必须使用 MATLAB 内置函数或官方工具箱实现。ONNX 模型导入是唯一例外（需要 Deep Learning Toolbox 且为可选模块）。

---

## 3. 项目架构：三阶段流水线

```
输入视频帧 ──▶ [模块一] 运动估计 ──▶ T_raw (3×3×N)
                     │
                     ▼
              [模块二] 运动分解与平滑 ──▶ T_smoothed (3×3×N)
                     │
                     ▼
              [模块三] 帧合成与去模糊 ──▶ 稳定帧输出
```

### 模块间数据契约（不可破坏）

- **模块一 → 模块二**：`T_sequence`，格式为 `3×3×N double`，每帧的全局变换矩阵（仿射或投影）。第一帧必须是 `eye(3)`。
- **模块二 → 模块三**：`T_smoothed`，格式同上。平滑策略可通过 `smooth_strategy` 参数切换（`'markov'` | `'gaussian_relative'` | `'gaussian_absolute'`）。
- **模块三输出**：`stabilizedFrame`，`uint8 H×W×3`，与原始帧同尺寸（或裁剪后统一尺寸）。

### 参考论文速查

- **14_LightStab (CVPR 2026)**：整体架构参考、多检测器协作、因果光流融合、多线程异步。**最重要的引用。**
- **17_中北大学 (MDPI 2025)**：相对坐标马尔可夫平滑、动态注意力掩码。**第二重要的引用。**
- **12_门控时空注意力 (CVPR 2021)**：去模糊子模块核心参考。
- **07_GoPro (CVPR 2017)**：评估范式、模糊核物理建模。
- 全部 17 篇论文详见 `papers/00_技术选型_从17篇论文到可实施方案.md`。

---

## 4. MATLAB 编码规范

### 4.1 函数编写

- 每个 `.m` 文件包含一个主函数，以及若干局部辅助函数（放在文件末尾，用 `%%` 分隔）。
- 函数签名使用 `arguments` 块做参数验证，不手写 `nargin` 检查。每个参数在 `arguments` 块中声明类型和默认值。
- 函数体不超过 80 行为佳。如果超过，把子逻辑抽成局部函数。
- 所有函数必须在文件头部注释中写明 INPUT、OUTPUT、依赖的 MATLAB 函数、TODO 列表。
- 写代码之前确认自己的角色，尽量不要修改其他角色的代码。

**示例：**

```matlab
function [result, diagnostics] = my_function(input, params)
    arguments
        input (:,:) double
        params struct = struct()
    end
    % 参数默认值
    if ~isfield(params, 'threshold'), params.threshold = 0.5; end
    % ... 业务逻辑 ...
end
```

### 4.2 命名规范

| 类型 | 规范 | 示例 |
|------|------|------|
| 函数文件 | `snake_case.m` | `detect_keypoints.m` |
| 函数名 | 与文件名一致 | `function [kp, scores] = detect_keypoints(...)` |
| 变量 | `camelCase` | `prevFrame`, `matchScores` |
| 结构体字段 | `camelCase` | `diagnostics.inlierRatio` |
| 常量 | `UPPER_SNAKE_CASE` | `MAX_FRAMES` |
| 模块主入口 | `run_<module_name>.m` | `run_motion_estimation.m` |
| 参数字典 | 统一命名为 `params`，永不命名为 `p` 或 `opt` | |

### 4.3 参数传递约定

本项目统一使用 `struct` 作为参数传递载体。每个模块的主入口函数接收一个 `params` struct，并将其子字段解包传递给子函数。不要使用 `varargin` 或 `'Name', value` 对。

**示例：**

```matlab
function run_motion_estimation(prevFrame, currFrame, params)
    detect_params    = safeField(params, 'detect_params', struct());
    match_params     = safeField(params, 'match_params', struct());
    % ...
end
```

每个子模块函数从 `params` 中读取自己需要的字段，使用 `isfield` 或项目提供的 `safeField` 辅助函数设置默认值。

### 4.4 诊断信息

所有模块函数必须返回一个 `diagnostics` struct，包含该函数的运行耗时（`*_time_ms`）和关键统计量（内点率、匹配数、模糊核长度等）。这为后续消融实验和性能分析提供数据。

`diagnostics` 字段命名遵循 `camelCase`，耗时字段以 `_time_ms` 结尾。

### 4.5 注释原则

- 解释「为什么这样做」而非「代码在做什么」。MATLAB 代码本身已经说明了后者。
- 引用论文时标注论文编号：`参考论文 14_LightStab (CVPR 2026) 第 3.1 节`
- 用 `TODO` 标记待实现的代码块。`TODO` 后写清楚「谁来做」和「做什么」：`TODO: 角色二实现 SIFT 检测器调用`
- 修改他人代码时，在修改处上方添加 `FIXME` 注释说明原因。

### 4.6 错误处理

- 输入参数非法时使用 `error('描述: %s', var)`，提供明确的错误消息。
- 可恢复的异常（如匹配点不足）使用 `warning`，并返回合理默认值（如 `eye(3)`）。
- 不吞异常。每个 `try-catch` 必须在 `catch` 块中输出有意义的信息。

### 4.7 图像数据格式

- 所有帧统一为 `uint8` 类型、`H×W×3` 彩色图（或 `H×W` 灰度图）。
- 在模块内部灰度化时使用 `rgb2gray`，处理后如需还原彩色则通过 YCbCr 色彩空间在亮度通道上操作。
- 坐标约定：`[x, y]`，x 为列索引（水平）、y 为行索引（垂直）。与 MATLAB 矩阵索引 `(row, col)` 相反。

---

## 5. 工作流模式

在修改或创建新功能时，严格按照以下四步执行：

### 步骤一：思考与计划

先阅读相关模块的 `run_*.m` 主入口文件，理解该模块在整个流水线中的位置、输入输出接口、以及依赖的其他子函数。输出一个简短的「实施计划」：列出要修改的文件、修改内容、以及修改后需要同步更新的调用方。

### 步骤二：编码

基于实施计划编写代码。确保：
- 函数签名三要素：`arguments` 参数块 + 输入验证 + 默认值
- 返回 `diagnostics` struct（含有耗时字段）
- 在注释中引用论文编号
- 保持函数体短小（<80 行）

### 步骤三：验证

在修改的函数文件底部添加一段 `%% 自测` 注释块，包含一个最小可运行的测试用例（使用合成数据或项目提供的自拍测试视频）。确保 `run` 该段能无报错运行。

### 步骤四：汇报

在 Git commit message 中说明：修改了什么、为什么修改、影响了哪些其他文件。一个清晰的历史记录比冗长的 PR 描述更重要。

---

## 6. 性能约束

- **因果性**：所有帧级操作不能访问未来帧。当前帧 t 的处理只依赖 ≤t 的帧。
- **单帧延迟目标**：每帧处理时间 < 100 ms（即 >10 fps）。如果某模块超过此阈值，优先降低计算精度（降采样、减少金字塔层数）而非牺牲在线性。
- **内存**：不要一次性加载整个视频到内存。逐帧读取、逐帧处理、逐帧写出。只在模块二中需要一次性获取全序列变换矩阵做批量平滑（这是可接受的：变换矩阵 3×3×N 的内存占用远小于视频帧）。
- **并行**：GUI 中用 `parfeval` 将处理循环推到后台 worker，避免阻塞 UI 线程。

---

## 7. 禁止事项

- **禁止**引入 Python、C++ MEX 或任何非 MATLAB 原生依赖（ONNX 模型导入除外且为可选）。
- **禁止**硬编码文件路径。所有路径通过 `params` struct 传入或使用相对路径。
- **禁止**跳过 `arguments` 块进行手动参数类型检查。
- **禁止**修改其他模块的 `run_*.m` 主入口函数签名（INPUT/OUTPUT 契约是跨模块约定，单方面改动会破坏集成）。
- **禁止**使用已被 MATLAB 官方标记为 `removed` 或 `not recommended` 的函数（如 `avifile`、`mmreader` 等）。
- **禁止**在未阅读本文档的情况下进行大规模代码修改。

---

## 8. 项目特定约定

### 8.1 联合调试标记

当你的代码被另一个角色调用时，在 `diagnostics` struct 中填充尽可能多的统计信息。对方可能不熟悉你的模块内部逻辑，`diagnostics` 是他们排查「输入对但输出错」的唯一线索。

### 8.2 算法评分权重

作业评分公式：**抗抖动效果 (60%) + 算法效率 (40%)**。每个设计决策都要能回答「这个选择对效果提升多少、对速度牺牲多少」。如果不能量化回答，说明思考不够。

### 8.3 论文引用

每个模块的核心技术选择必须引用至少一篇论文。引用编号与 `papers/` 目录中的编号一致。论文的完整 GB/T 7714 引用格式从 Google Scholar 获取。

### 8.4 自测数据

在正式测试素材发放前，使用 `data/test_videos/` 目录下的自拍视频做调试。自拍视频应覆盖：手持步行、静止站立、快速扫视、上楼梯/骑行颠簸等典型场景。每段视频 10-20 秒，分辨率 1080p 或 720p。

---

## 9. 文件清单（修改代码前先看这里）

| 文件 | 负责角色 | 核心功能 |
|------|---------|---------|
| `src/init_project.m` | 全体 | 项目初始化（路径 + 工具箱检查） |
| `src/main_pipeline.m` | 项目负责人 | 三阶段流水线主入口 |
| `src/motion_estimation/detect_keypoints.m` | 角色二 | SIFT+SURF 双检测器 + NMS + 网格均匀化 |
| `src/motion_estimation/match_keypoints.m` | 角色二 | 特征匹配 + Lowe's ratio test |
| `src/motion_estimation/compute_optical_flow.m` | 角色三 | 4 种因果光流算法骨架 |
| `src/motion_estimation/fuse_motion_field.m` | 角色三 | 稀疏关键点引导光流融合 |
| `src/motion_estimation/estimate_global_transform.m` | 角色二+三 | RANSAC 仿射/投影拟合 |
| `src/motion_estimation/run_motion_estimation.m` | 角色二+三 | 模块一主入口 |
| `src/motion_smoothing/decompose_affine_params.m` | 角色四 | 6 自由度仿射参数提取 |
| `src/motion_smoothing/relative_coordinate_model.m` | 角色五 | 相对坐标建模 + 逆变换 |
| `src/motion_smoothing/markov_window_smooth.m` | 角色五 | 马尔可夫窗口约束平滑 |
| `src/motion_smoothing/gaussian_smooth.m` | 角色四+五 | 基线高斯平滑（3 种方法） |
| `src/motion_smoothing/run_motion_smoothing.m` | 角色四+五 | 模块二主入口 |
| `src/frame_synthesis/warp_frame.m` | 角色六 | 仿射 warp + 边界处理 |
| `src/frame_synthesis/estimate_blur_kernel.m` | 角色六 | 运动参数 → 模糊核 PSF |
| `src/frame_synthesis/wiener_deblur.m` | 角色六 | 频域维纳/Lucy/Blind 去卷积 |
| `src/frame_synthesis/run_frame_synthesis.m` | 角色六 | 模块三主入口 |
| `src/evaluation/compute_psnr_ssim.m` | 角色八 | 帧间 PSNR + SSIM |
| `src/evaluation/compute_stabilization_ratio.m` | 角色八 | 稳定比 SR |
| `src/evaluation/visualize_trajectory.m` | 角色八 | 累积轨迹对比图 |
| `src/evaluation/visualize_frame_comparison.m` | 角色八 | 2×K 帧对比可视化 |
| `src/evaluation/run_ablation_study.m` | 角色八 | 消融实验自动化 |
| `src/app/stabilization_gui.mlapp` | 角色七 | App Designer 主界面（薄 GUI 层，编排三阶段流水线） |
| `src/app/phase_worker.m` | 角色七 | parfeval 后台 Worker（串联模块一→二→三，DataQueue 通信） |
| `src/app/trajectory_viewer.m` | 角色七 | 运动轨迹可视化子窗口（调用 visualize_trajectory） |
| `src/utils/load_video.m` | 全体 | 视频加载（cell/array 双格式） |
| `src/utils/save_video.m` | 全体 | 视频编码输出 |
| `src/utils/timer_utils.m` | 全体 | 嵌套计时器类 (TimerStack) |

---

> **最后提醒**：这份文件本身就是活文档。如果项目约定发生变更（如新增模块、调整接口契约、更换技术方案），第一时间更新此文件，并通知所有成员。
