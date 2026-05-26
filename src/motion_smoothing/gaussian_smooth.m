%% gaussian_smooth.m —— 基线高斯平滑
% 编码规范：参见项目根目录 AGENTS.md
% 角色四 & 五协作实现
%
% 功能：对仿射参数序列做低通滤波，实现三种基线平滑方法。
% 这是消融实验中的 baseline 方案——效果不如马尔可夫平滑，但实现简单，
% 用来证明相对坐标 + 窗口约束带来的增益。
%
% 三种方法：
%   1. 'gaussian'    - 手动 1D 高斯卷积（与外积 imgaussfilt 等效，不依赖额外 toolbox）
%   2. 'butterworth'  - Butterworth IIR 零相位滤波（'butter' + 'filtfilt'）
%   3. 'smoothdata'   - MATLAB 内置 smoothdata（最简单，但控制粒度最粗）
%
% 为什么在高斯平滑前先做参数分解？
%   直接平滑 3×3 变换矩阵的 9 个元素会破坏仿射约束（如正交性）。
%   在 6 参数域内对各参数独立平滑，能保持变换矩阵的物理可解释性。
%   代价：各参数独立滤波忽略了参数间的耦合关系（此为消融实验验证点）。
%
% INPUT:
%   paramSequence - N×6，仿射参数序列（绝对域或相对域均可）
%   params        - 参数字典
%     .method        - 'gaussian' | 'butterworth' | 'smoothdata'，默认 'gaussian'
%     .sigma         - 平滑强度（帧），默认 5
%     .cutoff_order  - Butterworth 滤波器阶数（仅 method='butterworth'），默认 4
%
% OUTPUT:
%   paramSmoothed - N×6，平滑后参数序列
%   diagnostics   - struct
%     .method              - 使用的方法
%     .sigma               - 平滑强度
%     .var_reduction_ratio - 各参数平滑前后方差比 [1×6]
%
% 注意：此函数不区分在线/离线模式（高斯平滑天然非因果，默认零相位）。
%       若需因果要求，使用 gaussian_causal 局部函数（仅使用过去帧）。
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
    if ~isfield(params, 'causal'),       params.causal = false; end

    N = size(paramSequence, 1);
    sigma = params.sigma;

    switch params.method
        case 'gaussian'
            kernel = gaussian_kernel_1d(sigma);
            if params.causal
                paramSmoothed = gaussian_causal(paramSequence, kernel);
            else
                paramSmoothed = zeros(N, 6);
                for j = 1:6
                    paramSmoothed(:,j) = conv(paramSequence(:,j), kernel, 'same');
                end
            end

        case 'butterworth'
            cutoff_norm = min(1 / sigma, 0.95);
            [b, a] = butter(params.cutoff_order, cutoff_norm, 'low');
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
            error('不支持的平滑方法: %s。可选: gaussian | butterworth | smoothdata', params.method);
    end

    var_before = var(paramSequence, 0, 1);
    var_after  = var(paramSmoothed, 0, 1);
    diagnostics = struct(...
        'method', params.method, ...
        'sigma', sigma, ...
        'causal', params.causal, ...
        'var_reduction_ratio', var_after ./ max(var_before, 1e-10));
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
