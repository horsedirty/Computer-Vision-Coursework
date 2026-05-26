% estimate_blur_kernel.m —— 从运动参数估计模糊核 PSF
% 编码规范：参见项目根目录 AGENTS.md
% 角色六负责实现
%
% 功能：利用模块二平滑掉的「抖动分量」来估计运动模糊核的点扩散函数 (PSF)。
% 物理直觉：相机曝光时间内的位移 = 运动模糊的方向和长度。
%
% 数学模型：
%   T_raw     - 原始相机路径（含抖动和有意运镜）
%   T_smoothed - 平滑后的理想路径（仅含有意运镜）
%   被平滑掉的抖动 = T_smoothed^{-1} · T_raw（修正变换）
%   抖动平移分量 dx, dy → 曝光时间内运动方向和长度 → 线性运动模糊核
%
% 参考论文：07_GoPro 手持去模糊（模糊核物理建模、线性运动近似）
%          16_CompEvent（频域 PSF 估计思路）
%
% INPUT:
%   T_raw       - 3×3，当前帧的原始变换矩阵
%   T_smoothed  - 3×3，当前帧的平滑后变换矩阵
%   frameIndex  - 当前帧索引（保留用于未来扩展，如邻帧平均）
%   params      - 参数字典
%     .kernelLength   - 最大模糊核长度（像素），默认 31
%     .avgWindow      - 估计模糊时平均的邻帧数，保留参数（当前版本单帧估计）
%     .minBlurLen     - 最小模糊长度阈值，低于此值视为无模糊，默认 0.5
%     .motionScale    - 运动 → 模糊长度缩放因子，默认 1.0
%                       曝光时间越长，该值越大
%
% OUTPUT:
%   psf         - kernelLength×kernelLength double，归一化模糊核
%                 若 blurLen < minBlurLen，返回标量 1（表示无模糊）
%   blurDir     - 模糊方向（弧度），范围 [-π, π]
%   blurLen     - 模糊长度（像素）
%   diagnostics - struct

function [psf, blurDir, blurLen, diagnostics] = estimate_blur_kernel(T_raw, T_smoothed, frameIndex, params)
    arguments
        T_raw (3,3) double
        T_smoothed (3,3) double
        frameIndex (1,1) double {mustBePositive, mustBeInteger}
        params struct = struct()
    end

    kernelLength = safeField(params, 'kernelLength', 31);
    minBlurLen   = safeField(params, 'minBlurLen', 0.5);
    motionScale  = safeField(params, 'motionScale', 1.0);

    t_start = tic;

    % ================================================================
    % 步骤 1: 提取抖动分量的平移部分
    % T_jitter = T_smoothed^{-1} * T_raw
    % 物理含义：从原始帧位置到平滑位置的修正变换
    % 该修正变换的平移量即为抖动平移（像素单位）
    % ================================================================
    T_correction = T_smoothed \ T_raw;

    dx_jitter = T_correction(1, 3);
    dy_jitter = T_correction(2, 3);

    % ================================================================
    % 步骤 2: 计算模糊方向和长度
    % 模糊方向 = jitter 平移向量的方向（弧度）
    % 模糊长度 = jitter 平移向量的模长 × motionScale
    % motionScale 可根据曝光时间/帧率动态调整
    % ================================================================
    blurLen = sqrt(dx_jitter^2 + dy_jitter^2) * motionScale;
    blurDir = atan2(dy_jitter, dx_jitter);

    % ================================================================
    % 步骤 3: 生成线状运动模糊核
    % 使用 MATLAB 内置 fspecial('motion', len, angle)
    % angle 需要从弧度转换为度
    % 如果模糊长度 < 阈值，返回标量 1（无模糊）
    % ================================================================
    if blurLen < minBlurLen
        psf = 1;
        blurLen = 0;
        blurDir = 0;
    else
        psfLen = min(max(ceil(blurLen), 1), kernelLength);
        psfAngle = rad2deg(blurDir);

        psf = fspecial('motion', psfLen, psfAngle);
        psf = psf / sum(psf(:));
    end

    elapsed = toc(t_start);

    diagnostics = struct(...
        'blurLen_pixels', blurLen, ...
        'blurDir_deg', rad2deg(blurDir), ...
        'dx_jitter', dx_jitter, ...
        'dy_jitter', dy_jitter, ...
        'psf_size', size(psf), ...
        'kernel_time_ms', elapsed * 1000);
end


function val = safeField(s, fieldname, default)
    if isfield(s, fieldname)
        val = s.(fieldname);
    else
        val = default;
    end
end


%% ====== 自测 ======
% 模拟一个纯平移抖动的场景：
% T_raw = eye(3); T_raw(1,3) = 3; T_raw(2,3) = 4;
% T_smoothed = eye(3);
% [psf, dir, len, diag] = estimate_blur_kernel(T_raw, T_smoothed, 1);
% fprintf('模糊长度=%.1fpx, 方向=%.1f°\n', len, rad2deg(dir));
% imshow(psf, []);
% title(sprintf('Motion Blur PSF (len=%.0f, angle=%.0f°)', len, rad2deg(dir)));
