%% warp_frame.m —— 仿射 Warp 帧合成
% 编码规范：参见项目根目录 AGENTS.md
% 角色六负责实现
%
% 功能：使用平滑后的全局变换矩阵对原始帧做几何变换（warp），
% 生成稳定帧。包含边界反射填充和裁剪处理。
%
% 参考论文：06_深度运动盲视频防抖（全帧输出策略）
%
% INPUT:
%   rawFrame    - 原始帧，uint8 H×W×3
%   T           - 3×3 变换矩阵（平滑后的）
%   params      - 参数字典
%     .fillMethod     - 边界外填充方式: 'symmetric' | 'replicate' | 'none'
%                       默认 'symmetric'
%     .cropEnabled    - 是否裁剪黑边，默认 true
%     .cropMargin     - 裁剪比例（相对于最大平移幅值），默认 1.2
%     .outputSize     - 输出尺寸 [H_out, W_out]，默认保持原始尺寸
%
% OUTPUT:
%   warpedFrame - uint8，warp 后的稳定帧
%   cropRect    - [x, y, w, h]，实际裁剪区域（供恢复参考）
%   diagnostics - struct

function [warpedFrame, cropRect, diagnostics] = warp_frame(rawFrame, T, params)
    arguments
        rawFrame (:,:,:) uint8
        T (3,3) double
        params struct = struct()
    end

    if ~isfield(params, 'fillMethod'),   params.fillMethod = 'symmetric'; end
    if ~isfield(params, 'cropEnabled'),  params.cropEnabled = true; end
    if ~isfield(params, 'cropMargin'),   params.cropMargin = 1.2; end

    [H, W, ~] = size(rawFrame);
    t_start = tic;

    % === 创建仿射变换对象 ===
    % TODO: 验证 T 为仿射（第 3 行 = [0 0 1]），否则提取仿射子矩阵
    % tform = affine2d(T');  % 注意: MATLAB affine2d 要求 T 的转置
    % TODO: 如果 T 是投影变换，改用 projective2d(T')

    % === 执行 Warp ===
    % TODO: warped = imwarp(rawFrame, tform, 'FillValues', 0);
    % 注：imwarp 默认填充 0（黑色）。
    warpedFrame = rawFrame;  % 占位

    % === 边界反射填充 ===
    % TODO: 统计 warp 后四边各有多少全黑像素行/列
    % 对黑边区域做反射填充：warped = padarray(warped(valid_rows, valid_cols), pad_size, 'symmetric', 'both');
    switch params.fillMethod
        case 'symmetric'
            % TODO: warpedFrame = padarray(cropped_interior, [top_pad, bottom_pad; left_pad, right_pad], 'symmetric');
        case 'replicate'
            % TODO: 同上，'replicate' 模式
        case 'none'
            % 不做填充，保留黑边
    end

    % === 裁剪 ===
    cropRect = [1, 1, W, H];  % 默认全图
    if params.cropEnabled
        % TODO: 计算最大平移幅值（从 T 的 dx, dy 估计）
        % maxShiftX = abs(T(1,3)) * cropMargin;
        % maxShiftY = abs(T(2,3)) * cropMargin;
        % 确定裁剪区域（保持长宽比）
        % cropRect = [maxShiftX, maxShiftY, W-2*maxShiftX, H-2*maxShiftY];
        % warpedFrame = imcrop(warpedFrame, cropRect);
    end

    % === 缩放到输出尺寸 ===
    % if isfield(params, 'outputSize')
    %     warpedFrame = imresize(warpedFrame, params.outputSize);
    % end

    elapsed = toc(t_start);
    diagnostics = struct(...
        'fillMethod', params.fillMethod, ...
        'cropEnabled', params.cropEnabled, ...
        'cropRect', cropRect, ...
        'pixel_retention', (cropRect(3)*cropRect(4)) / (W*H), ...
        'warp_time_ms', elapsed * 1000);
end
