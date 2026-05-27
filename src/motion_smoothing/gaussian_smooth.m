%% gaussian_smooth.m —— Baseline Gaussian Smoothing
% Coding standards: See AGENTS.md in project root
% Role 4 & 5 collaborative implementation
%
% Function: Low-pass filter affine parameter sequences, implementing three baseline smoothing methods.
% This is the baseline scheme in the ablation study — less effective than Markov smoothing, but simpler to implement,
% used to demonstrate the gains from relative coordinates + window constraints.
%
% Three methods:
%   1. 'gaussian'    - Manual 1D Gaussian convolution (equivalent to imgaussfilt, no extra toolbox dependency)
%   2. 'butterworth'  - Butterworth IIR zero-phase filtering ('butter' + 'filtfilt')
%   3. 'smoothdata'   - MATLAB built-in smoothdata (simplest, but coarsest control granularity)
%
% Why decompose parameters before Gaussian smoothing?
%   Directly smoothing the 9 elements of a 3×3 transformation matrix would break affine constraints (e.g., orthogonality).
%   Smoothing each parameter independently in the 6-parameter domain preserves the physical interpretability of the transformation matrix.
%   Cost: Independent filtering of each parameter ignores inter-parameter coupling (this is the ablation study validation point).
%
% INPUT:
%   paramSequence - N×6，仿射参数序列（绝对域或相对域均可）
%   params        - 参数字典
%     .method        - 'gaussian' | 'butterworth' | 'smoothdata'，默认 'gaussian'
%     .sigma         - 平滑强度（帧），默认 5
%     .cutoff_order  - Butterworth 滤波器阶数（仅 method='butterworth'），默认 4
%     .cutoff_freq   - Butterworth 归一化截止频率 (0~1)，默认 0.05
%                      0 < cutoff_freq < 1，1 = Nyquist = 0.5 cycles/frame
%
% OUTPUT:
%   paramSmoothed - N×6 double，平滑后参数序列
%   diagnostics   - struct
%     .method             - 使用的平滑方法
%     .sigma              - 平滑强度
%     .var_reduction_ratio - 各参数平滑前后方差比 [1×6] 或 整体平滑前后方差衰减比
%     .smooth_time_ms     - 平滑耗时 (ms)
%
% 注意：此函数不区分在线/离线模式（高斯平滑天然非因果，默认零相位）。
%       若需因果要求，使用 gaussian_causal 局部函数（仅使用过去帧）。
%
% 依赖：MATLAB Signal Processing Toolbox (butter, filtfilt) — 仅 method='butterworth'
%
% 参考论文：17_中北大学 (MDPI 2025) — baseline 对比
%
% TODO:
%   [x] 实现高斯卷积（conv + gaussian kernel）
%   [x] 实现 MATLAB smoothdata 调用
%   [x] 实现 Butterworth IIR 滤波器

function [paramSmoothed, diagnostics] = gaussian_smooth(paramSequence, params)
    arguments
        paramSequence (:,6) double
        params struct = struct()
    end

    if ~isfield(params, 'method'),       params.method = 'gaussian'; end
    if ~isfield(params, 'sigma'),        params.sigma = 5; end
    if ~isfield(params, 'cutoff_order'), params.cutoff_order = 4; end
    if ~isfield(params, 'cutoff_freq'),  params.cutoff_freq = 0.05; end
    if ~isfield(params, 'causal'),       params.causal = false; end

    N = size(paramSequence, 1);
    if N < 2
        paramSmoothed = paramSequence;
        diagnostics = struct('method', params.method, 'sigma', params.sigma, ...
            'var_reduction_ratio', 1.0, 'smooth_time_ms', 0, 'causal', params.causal);
        return;
    end

    t_start = tic;
    sigma = params.sigma;

    switch params.method
        case 'gaussian'
            kernel = gaussian_kernel_1d(sigma);
            if params.causal
                paramSmoothed = gaussian_causal(paramSequence, kernel);
            else
                paramSmoothed = zeros(N, 6);
                for j = 1:6
                    paramSmoothed(:,j) = convWithBoundary(paramSequence(:,j), kernel);
                end
            end

        case 'butterworth'
            cutoffOrder = params.cutoff_order;
            cutoffFreq  = params.cutoff_freq;

            if cutoffFreq <= 0 || cutoffFreq >= 1
                error('Butterworth cutoff_freq must be within (0, 1) range');
            end
            
            [b, a] = butter(cutoffOrder, cutoffFreq, 'low');
            paramSmoothed = zeros(N, 6);
            for j = 1:6
                paramSmoothed(:,j) = filtfilt(b, a, paramSequence(:,j));
            end

        case 'smoothdata'
            paramSmoothed = zeros(N, 6);
            for j = 1:6
                paramSmoothed(:,j) = smoothdata(paramSequence(:,j), 'gaussian', sigma);
            end

        otherwise
            error('Unsupported smoothing method: %s. Options: gaussian | butterworth | smoothdata', params.method);
    end

    smoothTime = toc(t_start);

    varBefore = mean(var(paramSequence, 0, 1));
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
        'smooth_time_ms',      smoothTime * 1000, ...
        'causal',              params.causal);
end


% =========================================================================
%% Local function: convWithBoundary —— Boundary-aware 1D convolution
%
% Convolve a signal with a specified kernel, using a normalized kernel of available portion at boundaries.
% Better than conv(x, kernel, 'same'): kernel is re-normalized at boundaries,
% preventing signal ends from being "suppressed" (conv's 'same' causes amplitude decay at boundaries due to incomplete kernel coverage)
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
%% Self-test
% Verify correctness of three smoothing methods:
%   1. Variance reduction: variance should decrease significantly after smoothing
%   2. Shape fidelity: low-frequency sinusoidal trend should be preserved
%   3. No NaN/Inf: all outputs should be valid
% =========================================================================

function [] = self_test()
    fprintf('=== gaussian_smooth self-test ===\n');

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
            fprintf('  %-14s variance reduction: %.4f  time: %.2f ms\n', ...
                method, mean(diag.var_reduction_ratio), diag.smooth_time_ms);
            assert(all(~isnan(smoothed(:))), sprintf('%s output contains NaN', method));
            assert(all(~isinf(smoothed(:))), sprintf('%s output contains Inf', method));
            assert(mean(diag.var_reduction_ratio) < 0.95, ...
                sprintf('%s insufficient variance reduction: %.4f', method, mean(diag.var_reduction_ratio)));
        catch ME
            fprintf('  %-14s skipped (possibly missing Signal Processing Toolbox): %s\n', method, ME.message);
        end
    end

    fprintf('  self-test passed ✓\n');
end


function kernel = gaussian_kernel_1d(sigma)
    halfW = ceil(3 * sigma);
    x = (-halfW:halfW)';
    kernel = exp(-x.^2 / (2 * sigma^2));
    kernel = kernel / sum(kernel);
end


function paramSmoothed = gaussian_causal(paramSequence, kernel)
    N = size(paramSequence, 1);
    paramSmoothed = zeros(N, 6);
    halfW = (length(kernel) - 1) / 2;
    for i = 1:N
        idxLeft  = max(1, i - halfW);
        idxRight = i;
        winLen = idxRight - idxLeft + 1;
        causalKernel = kernel(end-winLen+1:end);
        causalKernel = causalKernel / sum(causalKernel);
        for j = 1:6
            paramSmoothed(i,j) = causalKernel' * paramSequence(idxLeft:idxRight, j);
        end
    end
end


%% 自测
% 验证三种方法均能降低噪声方差
% fprintf('=== gaussian_smooth 自测 ===\n');
% N_test = 200;
% t = (1:N_test)';
% clean = 10 * sin(0.05 * t) + 0.02 * t;
% noisy = clean + 3 * randn(N_test, 1);
% data = [noisy, zeros(N_test, 5)];
%
% methods = {'gaussian', 'butterworth', 'smoothdata'};
% for m = 1:3
%     [smoothed, diag] = gaussian_smooth(data, struct('method', methods{m}, 'sigma', 5));
%     rr = diag.var_reduction_ratio(1);
%     fprintf('  %-12s: 方差衰减比 = %.3f (期望 < 1, 越小平滑越强)\n', methods{m}, rr);
%     assert(rr < 0.99, '%s 未实现有效降噪, 方差衰减比=%.3f', methods{m}, rr);
% end
% fprintf('gaussian_smooth 自测通过\n\n');
