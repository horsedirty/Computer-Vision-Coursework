# 交接文档：消除防抖黑边（时域运动补边 / motion inpainting）

> 状态：功能已实现并验证可用，**改动尚未 commit**。当前分支 `test`。

## 1. 背景与目标
原防抖流水线输出有较大黑边。原 `crop` 模式靠“中心裁剪+放大”藏黑边，会损失视野和分辨率。
本次新增 **`inpaint` 模式**：保留整幅画面、不裁剪不缩放，用相邻帧的真实像素 warp 过来
填补每帧边缘的黑边空洞（即 Matsushita et al. 2006《Full-Frame Video Stabilization with
Motion Inpainting》/ OpenCV videostab 的思路）。

## 2. 关键技术决策（重要）
- **没有用 OpenCV videostab 的 MotionInpainter/ConsistentMosaicInpainter**：
  实测本机 `opencv-python 4.13` 无 `cv2.videostab`，且即便装 `opencv-contrib-python`，
  videostab 的高级 inpainter 类**没有 Python 绑定**（C++ only）。所以自实现该算法。
- **依赖不变**：只用现有 `opencv-python + numpy + scipy`。残留极小空洞用 `cv2.inpaint`
  (Telea，主包自带) 收尾。**无需重装环境**。
- 用户已确认：策略=时域填充，可加 contrib（但实际用不上，见上）。

## 3. 改动的文件
| 文件 | 改动 |
|---|---|
| `border_fill.py` | **新增**。补边核心：`neighbor_transform` / `temporal_fill` / `_warp_with_mask` / `_feather_seam` / `fill_frame` |
| `smoothing.py` | `smooth_trajectory` 的 `diag` 里新增 `abs_transforms`（绝对轨迹 A_i，补边算邻帧采样矩阵用） |
| `synthesis.py` | `synthesize` 新增 `border_mode/abs_transforms/fill_window/fill_feather` 参数；新增 `inpaint` 分支与 `_FrameWindow`（滑窗读帧）、`_apply_sharpen` |
| `stabilize.py` | `run`/CLI 新增 `--border {crop,inpaint}`、`--fill-window`、`--fill-feather`，并把 `abs_transforms` 透传给 `synthesize` |

> 注：之前尝试写 `test_border_fill.py` 被用户拒绝，改为运行期验证；该文件**未创建**。

## 4. 用法
```bash
# 全幅补边（无黑边、不裁剪）
python stabilize.py 输入.mp4 -o 输出.mp4 --border inpaint
# 可选：--fill-window 20（前后取多少帧补边来源）  --fill-feather 8（接缝羽化）
# 默认仍是 crop 模式（不传 --border 时行为不变，向后兼容）
```

## 5. 算法核心（一句话）
已验证的逐帧 dst->src 矫正矩阵满足 `O_i(x)=F_i(W_i·x)`；设绝对轨迹 `A_i`，则用邻帧 j 的
源像素填当前画布空洞的采样矩阵为：
```
G_{i<-j} = A_j · A_i^{-1} · W_i      (j==i 时退化为 W_i，与主路径自洽)
```
即 `border_fill.neighbor_transform`。每帧：先 warp 自身得 base+空洞 mask → 近邻优先逐帧
warp 进**空洞外接矩形 ROI** 增量填补（补满/到上限即停）→ 接缝羽化 → 残留用 `cv2.inpaint`。

## 6. 验证结果（已实跑）
- `平移.mp4`（369帧 1080p）：耗时 ~67s，输出**无黑边**（最坏纯黑像素 0.01%）。视觉检查
  `/tmp/frame_inpaint_179.png`、`/tmp/pingyi_inpaint_compare.mp4`：边缘填充自然、接缝几乎不可见。
- `平移旋转缩放复合2.mp4`（288帧）：耗时 ~64s，最坏纯黑 0.16%（验证旋转/缩放的仿射数学正确）。
- 纯函数自检（`neighbor_transform` 同帧恒等、`temporal_fill` 填洞/留洞）均通过。

## 7. 已知问题 / 下一步（按优先级）
1. **速度**：inpaint 约 67s/12s片（crop 仅 8s），瓶颈是逐邻帧的全源 warp。可优化：
   - `_warp_with_mask` 里每次 `np.full(全帧,255)` 建 mask，可复用/缩小源 ROI。
   - 邻帧 warp 可降采样做 mask 判定。
2. **大空洞质量**：复合运动下个别帧空洞达 25%，靠 `cv2.inpaint` 兜底处会有轻微涂抹/拉伸感
   （见 `/tmp/composite_worst.png`，整体可接受）。改进方向：扩大 `--fill-window`、或对大空洞
   做多帧加权/羽化混合而非 Telea inpaint。
3. **动态前景**：场景里有运动物体时，邻帧填充可能有轻微 ghosting（本测试集为主静态，未见明显问题）。
4. **README/文档**：`stabilizer/README.md` 已被改动（git status 显示 M），需补充 inpaint 模式说明。
5. **收尾**：改动未提交。建议跑通 `--compare` 出对比视频给老师看后再 commit。

## 8. 复现验证命令
```bash
cd stabilizer
../.venv/bin/python stabilize.py ../data/test_videos/平移.mp4 -o /tmp/out.mp4 --border inpaint --compare
# 扫描输出黑边比例见对话中脚本（cap.read 循环统计 max(channels)<8 的像素占比）
```
