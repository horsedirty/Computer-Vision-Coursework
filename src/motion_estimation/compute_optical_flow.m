%% compute_optical_flow.m —— 因果光流计算
% 编码规范：参见项目根目录 AGENTS.md
% 角色三负责实现
%
% 功能：在两帧之间计算稠密光流场。遵循因果约束——只用当前帧与前一帧，
% 不访问未来帧。输出稠密运动场供后续融合使用。
%
% INPUT:
%   prevFrame   - 前一帧，uint8 H×W 灰度图像
%   currFrame   - 当前帧，uint8 H×W 灰度图像
%   params      - 参数字典
%     .method     - 光流算法: 'Farneback' | 'HS' | 'LK' | 'LKDoG'
%                   默认 'Farneback'（稠密、效果好）
%     .pyramid    - Farneback 金字塔层数，默认 3
%     .scale      - 图像缩放因子（加速），默认 1.0
%
% OUTPUT:
%   flow        - opticalFlow 对象，包含 Vx, Vy, Magnitude, Orientation
%   diagnostics - struct，包含计算耗时、有效像素比例等
%
% 参考论文：
%   - 14_LightStab (CVPR 2026): 多检测器协作框架中的因果光流约束
%   - 10_CVPR2020: 光流作为防抖中间表示的范式验证
%   - 11_TIP2019: 在线处理因果性约束
%
% 依赖: Computer Vision Toolbox

function [flow, diagnostics] = compute_optical_flow(prevFrame, currFrame, params)
    arguments
        prevFrame (:,:) uint8
        currFrame (:,:) uint8
        params struct = struct()
    end

    if ~isfield(params, 'method'),  params.method = 'Farneback'; end
    if ~isfield(params, 'pyramid'), params.pyramid = 3; end
    if ~isfield(params, 'scale'),   params.scale = 1.0; end

    t_start = tic;

    % === 可选：缩放加速 ===
    % 对高分辨率视频可选下采样，以提速。光流内部金字塔已提供 coarse-to-fine 加速，
    % 外部缩放仅在输入超过 720p 时触发，降低内存和运算压力。
    % 参考论文 14_LightStab 第 3.1 节：多分辨率金字塔加速策略
    H_orig = size(prevFrame, 1);
    W_orig = size(prevFrame, 2);
    maxDim = max(H_orig, W_orig);

    if params.scale < 1.0 && params.scale > 0.1 && maxDim > 480
        prevWork = imresize(prevFrame, params.scale);
        currWork = imresize(currFrame, params.scale);
        flowVx = single([]);
        flowVy = single([]);
        flowMagnitude = single([]);
        flowOrientation = single([]);
    else
        prevWork = prevFrame;
        currWork = currFrame;
        scale_effective = 1.0;
    end

    if exist('scale_effective', 'var')
        scale_effective = 1.0;
    else
        scale_effective = params.scale;
    end

    % === 因果光流计算 ===
    % 第一帧初始化 reference，第二帧计算 forward flow。这是因果约束的核心。
    % 参考论文 14_LightStab 第 3.1 节。
    try
        switch params.method
            case 'Farneback'
                opticFlow = opticalFlowFarneback(...
                    'NumPyramidLevels', params.pyramid, ...
                    'PyramidScale', 0.5, ...
                    'NumIterations', 3, ...
                    'NeighborhoodSize', 15, ...
                    'FilterSize', 5);
                estimateFlow(opticFlow, prevWork);
                flow = estimateFlow(opticFlow, currWork);

            case 'HS'
                opticFlow = opticalFlowHS(...
                    'Smoothness', 1, ...
                    'VelocityDifference', 0, ...
                    'MaxIteration', 10);
                estimateFlow(opticFlow, prevWork);
                flow = estimateFlow(opticFlow, currWork);

            case 'LK'
                opticFlow = opticalFlowLK(...
                    'NoiseThreshold', 0.0039);
                estimateFlow(opticFlow, prevWork);
                flow = estimateFlow(opticFlow, currWork);

            case 'LKDoG'
                opticFlow = opticalFlowLKDoG(...
                    'NumFrames', 3, ...
                    'ImageFilterSigma', 1.5, ...
                    'GradientFilterSigma', 1, ...
                    'NoiseThreshold', 0.0039);
                estimateFlow(opticFlow, prevWork);
                flow = estimateFlow(opticFlow, currWork);

            otherwise
                error('不支持的光流方法: %s', params.method);
        end
    catch ME
        warning('光流计算失败 (%s), 返回空流场: %s', params.method, ME.message);
        elapsed = toc(t_start);
        diagnostics = struct(...
            'method', params.method, ...
            'elapsed_ms', elapsed * 1000, ...
            'status', 'failed', ...
            'error', ME.message);
        flow = [];
        return;
    end

    % === 若进行了缩放，将流场上采样回原尺寸 ===
    if scale_effective < 1.0 && ~isempty(flow)
        inv_scale = 1.0 / scale_effective;
        flowVx = imresize(flow.Vx, [H_orig, W_orig], 'bilinear') * single(inv_scale);
        flowVy = imresize(flow.Vy, [H_orig, W_orig], 'bilinear') * single(inv_scale);
        flowMagnitude = sqrt(flowVx.^2 + flowVy.^2);
        flowOrientation = atan2(flowVy, flowVx);
    end

    elapsed = toc(t_start);

    % === 诊断信息 ===
    if ~isempty(flow) && isa(flow, 'opticalFlow')
        vx = flow.Vx;
        vy = flow.Vy;
        mag = flow.Magnitude;
        valid = ~isnan(vx) & ~isnan(vy);
        valid_count = sum(valid(:));
        total_count = numel(vx);
        diagnostics = struct(...
            'method', params.method, ...
            'elapsed_ms', elapsed * 1000, ...
            'status', 'ok', ...
            'valid_pixel_ratio', valid_count / total_count, ...
            'mean_magnitude', mean(mag(valid), 'all'), ...
            'median_magnitude', median(mag(valid), 'all'), ...
            'p95_magnitude', prctile(mag(valid), 95, 'all'), ...
            'max_magnitude', max(mag(valid), [], 'all'), ...
            'scale', scale_effective, ...
            'pyramid_levels', params.pyramid, ...
            'frame_size', [H_orig, W_orig]);
    else
        diagnostics = struct(...
            'method', params.method, ...
            'elapsed_ms', elapsed * 1000, ...
            'status', 'empty', ...
            'scale', scale_effective);
    end
end


%% 自测（合成数据 + 四种光流方法对比）
%{
    fprintf('=== compute_optical_flow 自测 ===\n');

    % 生成两帧已知平移的合成图像
    H = 240; W = 320;
    frame1 = uint8(255 * (randn(H, W) * 0.1 + 0.5));
    frame1 = max(0, min(255, frame1));
    frame2 = imtranslate(frame1, [3.5, -2.0], 'FillValues', uint8(128));

    methods = {'Farneback', 'HS', 'LK', 'LKDoG'};
    for i = 1:numel(methods)
        params = struct('method', methods{i}, 'pyramid', 3, 'scale', 1.0);
        [flow, diag] = compute_optical_flow(frame1, frame2, params);
        if ~isempty(flow)
            fprintf('[%s] 耗时: %6.1f ms | 平均位移: %5.2f px | 有效率: %.2f\n', ...
                diag.method, diag.elapsed_ms, diag.mean_magnitude, diag.valid_pixel_ratio);
            fprintf('  中位数位移: %.2f | P95: %.2f | 最大: %.2f\n', ...
                diag.median_magnitude, diag.p95_magnitude, diag.max_magnitude);
        else
            fprintf('[%s] 失败: %s\n', methods{i}, diag.error);
        end
    end

    % 缩放加速测试
    fprintf('\n缩放加速测试:\n');
    for s = [1.0, 0.5, 0.25]
        p = struct('method', 'Farneback', 'pyramid', 3, 'scale', s);
        [~, d] = compute_optical_flow(frame1, frame2, p);
        fprintf('  scale=%.2f: %.1f ms\n', s, d.elapsed_ms);
    end
%}
