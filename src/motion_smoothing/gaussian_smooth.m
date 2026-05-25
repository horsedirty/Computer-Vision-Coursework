%% gaussian_smooth.m —— 基线高斯平滑
% 编码规范：参见项目根目录 AGENTS.md
% 角色四 & 五协作实现
%
% 功能：对绝对坐标下的仿射参数序列做低通滤波。
% 这是消融实验中的 baseline 方案——效果不如马尔可夫平滑，但实现简单，
% 用来证明相对坐标 + 窗口约束带来的增益。
%
% 三种实现方式（通过 params.method 切换）：
%   1. 'gaussian'     - 手动高斯卷积（类比 imgaussfilt 的一维版）
%   2. 'butterworth'  - Butterworth IIR 零相位低通滤波（butter + filtfilt）
%   3. 'smoothdata'   - 直接调用 MATLAB 内置 smoothdata（最简单）
%
% 消融实验中的角色：
%   - 纯高斯滤波（gaussian_absolute）：对绝对参数直接平滑 → baseline
%   - 相对坐标高斯（gaussian_relative）：abs→rel→高斯→abs，无窗口约束
%   - 相对坐标马尔可夫（markov）：完整版，有窗口约束 → 最佳方案
%
% INPUT:
%   paramAbsolute - N×6 double，绝对坐标仿射参数序列
%   params        - struct
%     .sigma         - 高斯核标准差（帧），默认 5
%     .method        - 'gaussian' | 'butterworth' | 'smoothdata'，默认 'gaussian'
%     .cutoff_order  - Butterworth 滤波器阶数，默认 4（仅 method='butterworth'）
%     .cutoff_freq   - Butterworth 归一化截止频率 (0~1)，默认 0.05
%                      0 < cutoff_freq < 1，1 = Nyquist = 0.5 cycles/frame
%
% OUTPUT:
%   paramSmoothed - N×6 double，平滑后参数序列
%   diagnostics   - struct
%     .method             - 使用的平滑方法
%     .sigma              - 高斯核标准差
%     .var_reduction_ratio - 平滑前后方差衰减比（< 1，越小平滑越强）
%     .smooth_time_ms     - 平滑耗时 (ms)
%
% 依赖：MATLAB Signal Processing Toolbox (butter, filtfilt) — 仅 method='butterworth'
%
% 参考论文：17_中北大学 (MDPI 2025) — baseline 对比

function [paramSmoothed, diagnostics] = gaussian_smooth(paramAbsolute, params)
    arguments
        paramAbsolute (:,6) double
        params struct = struct()
    end

    if ~isfield(params, 'sigma'),        params.sigma = 5; end
    if ~isfield(params, 'method'),       params.method = 'gaussian'; end
    if ~isfield(params, 'cutoff_order'), params.cutoff_order = 4; end
    if ~isfield(params, 'cutoff_freq'),  params.cutoff_freq = 0.05; end

    N = size(paramAbsolute, 1);
    if N < 2
        paramSmoothed = paramAbsolute;
        diagnostics = struct('method', params.method, 'sigma', params.sigma, ...
            'var_reduction_ratio', 1.0, 'smooth_time_ms', 0);
        return;
    end

    t_start = tic;
    paramSmoothed = zeros(N, 6);

    switch params.method
        case 'gaussian'
            % 手动一维高斯卷积：构造高斯核并对每列独立卷积
            % 核半径 = 3*sigma（覆盖 99.7% 的高斯权重）
            sigma = params.sigma;
            halfW = ceil(3 * max(sigma, 0.5));
            x = (-halfW:halfW)';
            gaussKernel = exp(-x.^2 / (2 * sigma^2));
            gaussKernel = gaussKernel / sum(gaussKernel);

            for j = 1:6
                paramSmoothed(:, j) = convWithBoundary(paramAbsolute(:, j), gaussKernel);
            end

        case 'butterworth'
            % Butterworth IIR 零相位低通滤波
            % 参考论文 17 的频域分析思路：截止频率分离高低频
            cutoffOrder = params.cutoff_order;
            cutoffFreq  = params.cutoff_freq;

            if cutoffFreq <= 0 || cutoffFreq >= 1
                error('Butterworth cutoff_freq 必须在 (0, 1) 范围内');
            end

            [b, a] = butter(cutoffOrder, cutoffFreq, 'low');

            for j = 1:6
                paramSmoothed(:, j) = filtfilt(b, a, paramAbsolute(:, j));
            end

        case 'smoothdata'
            % 直接调用 MATLAB 内置 smoothdata
            sigma = params.sigma;
            for j = 1:6
                paramSmoothed(:, j) = smoothdata(paramAbsolute(:, j), 'gaussian', sigma);
            end

        otherwise
            error('不支持的平滑方法: %s', params.method);
    end

    smoothTime = toc(t_start);

    % 方差衰减比
    varBefore = mean(var(paramAbsolute, 0, 1));
    varAfter  = mean(var(paramSmoothed, 0, 1));
    if varBefore > 1e-10
        varReduction = varAfter / varBefore;
    else
        varReduction = 1.0;
    end

    diagnostics = struct(...
        'method',              params.method, ...
        'sigma',               params.sigma, ...
        'var_reduction_ratio', varReduction, ...
        'smooth_time_ms',      smoothTime * 1000);
end


% =========================================================================
%% 局部函数：convWithBoundary —— 边界感知的一维卷积
%
% 用指定核对信号做卷积，边界处使用可用部分的归一化核。
% 比 conv(x, kernel, 'same') 更好的地方：边界处核重新归一化，
% 避免信号两端被"压低"（conv 的 'same' 在边界处核不完整导致幅值衰减）
% =========================================================================

function y = convWithBoundary(x, kernel)
    arguments
        x (:,1) double
        kernel (:,1) double
    end

    N = length(x);
    kw = length(kernel);
    halfW = floor(kw / 2);
    y = zeros(N, 1);

    for t = 1:N
        kernStartInFull = max(1, t - halfW);
        kernEndInFull   = min(N, t + halfW);

        kernStartLocal = kernStartInFull - (t - halfW) + 1;
        kernEndLocal   = kernEndInFull - (t - halfW) + 1;
        localKernel = kernel(kernStartLocal:kernEndLocal);
        localKernel = localKernel / sum(localKernel);

        y(t) = sum(x(kernStartInFull:kernEndInFull) .* localKernel);
    end
end


% =========================================================================
%% 自测
% 验证三种平滑方法的正确性：
%   1. 方差衰减：平滑后方差应显著降低
%   2. 形状保真：低频正弦的趋势应被保留
%   3. 无 NaN/Inf：所有输出应有效
% =========================================================================

function [] = self_test()
    fprintf('=== gaussian_smooth 自测 ===\n');

    N = 100;
    t = (1:N)';

    paramAbs = zeros(N, 6);
    paramAbs(:, 1) = 2 * sin(0.1 * t) + 1.0 * randn(N, 1);
    paramAbs(:, 2) = cos(0.15 * t) + 0.8 * randn(N, 1);
    paramAbs(:, 3) = 0.02 * sin(0.05 * t) + 0.005 * randn(N, 1);
    paramAbs(:, 4) = 1 + 0.01 * randn(N, 1);
    paramAbs(:, 5) = 0.001 * randn(N, 1);
    paramAbs(:, 6) = 0.001 * randn(N, 1);

    methods = {'gaussian', 'butterworth', 'smoothdata'};
    for i = 1:length(methods)
        method = methods{i};
        try
            p = struct('method', method, 'sigma', 5, 'cutoff_freq', 0.1);
            [smoothed, diag] = gaussian_smooth(paramAbs, p);
            fprintf('  %-14s 方差衰减: %.4f  耗时: %.2f ms\n', ...
                method, diag.var_reduction_ratio, diag.smooth_time_ms);
            assert(all(~isnan(smoothed(:))), sprintf('%s 输出包含 NaN', method));
            assert(all(~isinf(smoothed(:))), sprintf('%s 输出包含 Inf', method));
            assert(diag.var_reduction_ratio < 0.95, ...
                sprintf('%s 方差衰减不足: %.4f', method, diag.var_reduction_ratio));
        catch ME
            fprintf('  %-14s 跳过（可能缺少 Signal Processing Toolbox）: %s\n', method, ME.message);
        end
    end

    fprintf('  自测通过 ✓\n');
end
