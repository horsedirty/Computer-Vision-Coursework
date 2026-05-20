%% estimate_blur_kernel.m —— 从运动参数估计模糊核 PSF
% 编码规范：参见项目根目录 AGENTS.md
% 角色六负责实现
%
% 功能：利用模块二平滑掉的「抖动分量」来估计运动模糊核的点扩散函数 (PSF)。
% 物理直觉：相机曝光时间内的位移 = 运动模糊的方向和长度。
%
% 数学模型：
%   原始帧的全局运动 = 平滑后的运动（有意运镜）+ 被平滑掉的抖动
%   被平滑掉的抖动 = 原始运动 - 平滑后运动
%   每一帧的"抖动"成分近似为曝光时间内的线性运动模糊核
%
% 参考论文：07_GoPro 手持去模糊（模糊核物理建模）
%
% INPUT:
%   T_raw       - N×3×3 或 3×3×N，原始变换矩阵序列
%   T_smoothed  - N×3×3 或 3×3×N，平滑后变换矩阵序列
%   frameIndex  - 当前帧索引
%   params      - 参数字典
%     .kernel_length  - 最大模糊核长度（像素），默认 31
%     .avgWindow      - 估计模糊时平均的邻帧数，默认 2（±2 帧）
%
% OUTPUT:
%   psf         - kernel_length×kernel_length double，归一化模糊核
%   blurDir     - 模糊方向（弧度）
%   blurLen     - 模糊长度（像素）
%   diagnostics - struct

function [psf, blurDir, blurLen, diagnostics] = estimate_blur_kernel(T_raw, T_smoothed, frameIndex, params)
    arguments
        T_raw
        T_smoothed
        frameIndex (1,1) double {mustBePositive, mustBeInteger}
        params struct = struct()
    end

    if ~isfield(params, 'kernel_length'), params.kernel_length = 31; end
    if ~isfield(params, 'avgWindow'),     params.avgWindow = 2; end

    % === 提取抖动分量 ===
    % T_jitter = T_raw - T_smoothed
    % 取抖动分量的平移部分 (dx, dy)
    % TODO: 从 T_raw(frameIndex) 和 T_smoothed(frameIndex) 提取 dx_jitter, dy_jitter

    % === 邻帧平均（平滑抖动估计） ===
    % TODO: 在 [frameIndex - avgWindow, frameIndex + avgWindow] 范围内
    % 取 dx_jitter 和 dy_jitter 的加权平均
    avg_dx = 0;
    avg_dy = 0;

    % === 计算模糊方向和长度 ===
    blurLen = sqrt(avg_dx^2 + avg_dy^2);
    blurDir = atan2(avg_dy, avg_dx);

    % === 限制模糊核长度 ===
    blurLen = min(blurLen, params.kernel_length);

    % === 生成线状运动模糊核 ===
    % TODO: 使用 fspecial('motion', blurLen, blurDir_deg)
    % if blurLen > 0.5
    %     psf = fspecial('motion', max(ceil(blurLen), 1), rad2deg(blurDir));
    %     psf = psf / sum(psf(:));  % 归一化
    % else
    %     psf = 1;  % 无模糊
    % end
    psf = 1;  % 占位：无模糊
    blurLen = 0;
    blurDir = 0;

    diagnostics = struct(...
        'blurLen_pixels', blurLen, ...
        'blurDir_deg', rad2deg(blurDir), ...
        'avg_dx', avg_dx, ...
        'avg_dy', avg_dy);
end
