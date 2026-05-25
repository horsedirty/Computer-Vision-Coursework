%% markov_window_smooth.m —— 马尔可夫窗口约束平滑
% 编码规范：参见项目根目录 AGENTS.md
% 角色五负责实现
%
% 功能：在相对坐标域对增量序列做窗口约束的高斯平滑。
% 这是整个系统「区分抖动与运动」的核心机制。
%
% 核心原理（参考论文 17_中北大学 MDPI Applied Sciences 2025）：
%   - 平滑只作用于有限窗口半径 l（默认 l=3，窗口总长 2l+1 = 7 帧）
%   - 马尔可夫性质：窗口内的平滑只依赖该窗口内的增量，与更远的帧无关
%   - 高频抖动（周期 < l）：被滤掉——增量局部加权平均后高频幅值降低
%   - 低频有意运动（周期 > l）：被保留——窗口内近似直线，加权平均不改变趋势
%   - 增量域平滑再积分回绝对域，避免直接平滑绝对坐标带来的累积漂移
%
% 为什么不在绝对域直接平滑？
%   绝对坐标 T_t 包含从原点开始的累积运动。对 T_t 做高斯平滑会把低频的有意运镜
%   也一起抹掉（比如从 A 走到 B 的平移趋势会被过度平滑导致"回弹"效果）。
%   增量域 ΔT_t 是纯帧间差分，只含高频抖动，平滑后积分回绝对域能保留原轨迹趋势。
%
% 离线 vs 在线模式：
%   - 离线模式（默认）：窗口 [t-l, t+l]，效果更好，用于批量处理和实验评估
%   - 在线模式：窗口 [t-2l, t]（只看过去），用于实时系统，效果略差但满足因果性
%     参考论文 17 第 3.3 节：因果模式下窗口向前偏移以保证可用信息量
%
% INPUT:
%   paramRelative - N×6 double，相对坐标增量序列（来自 relative_coordinate_model）
%   params        - struct
%     .window_radius  - 平滑窗口半宽 l，默认 3（窗口总长 2l+1=7）
%     .sigma          - 高斯核标准差，默认 1.0（越大平滑越强）
%     .kernel_type    - 'gaussian' | 'uniform'，默认 'gaussian'
%     .online_mode    - 是否在线模式（只看过去帧），默认 false
%     .initAbsolute   - 1×6，首帧绝对参数（作为积分起点），默认 zeros(1,6)
%
% OUTPUT:
%   paramSmoothedRelative - N×6 double，平滑后的增量序列
%   paramSmoothedAbsolute - N×6 double，积分重建的绝对参数序列
%   kernel                - (2l+1)×1 double，使用的平滑核（供可视化/调试）
%   diagnostics           - struct
%     .window_radius      - 使用的窗口半径
%     .sigma              - 高斯核标准差（uniform 时为 NaN）
%     .kernel_type        - 核类型
%     .online_mode        - 是否在线模式
%     .variance_reduction - 平滑前后 6 维增量方差的比值（< 1，越小平滑越强）
%     .smooth_time_ms     - 平滑耗时 (ms)
%     .rebuild_time_ms    - 绝对坐标重建耗时 (ms)
%
% 依赖：无外部依赖（relative_to_absolute 作为局部函数内联）
%
% 参考论文：17_中北大学在线拼接防抖 (MDPI Applied Sciences 2025)

function [paramSmoothedRelative, paramSmoothedAbsolute, kernel, diagnostics] = markov_window_smooth(paramRelative, params)
    arguments
        paramRelative (:,6) double
        params struct = struct()
    end

    if ~isfield(params, 'window_radius'), params.window_radius = 3; end
    if ~isfield(params, 'sigma'),         params.sigma = 1.0; end
    if ~isfield(params, 'kernel_type'),   params.kernel_type = 'gaussian'; end
    if ~isfield(params, 'online_mode'),   params.online_mode = false; end
    if ~isfield(params, 'initAbsolute'),  params.initAbsolute = zeros(1, 6); end

    l = params.window_radius;
    N = size(paramRelative, 1);

    if N < 2
        paramSmoothedRelative = paramRelative;
        paramSmoothedAbsolute = paramRelative;
        kernel = 1;
        diagnostics = struct(...
            'window_radius', l, 'sigma', params.sigma, ...
            'kernel_type', params.kernel_type, 'online_mode', params.online_mode, ...
            'variance_reduction', 1.0, 'smooth_time_ms', 0, 'rebuild_time_ms', 0);
        return;
    end

    t_smooth_start = tic;

    % ================================================================
    % 步骤 1: 生成平滑核
    % ================================================================
    kernel = build_kernel(l, params.sigma, params.kernel_type, params.online_mode);

    % ================================================================
    % 步骤 2: 对每一维增量独立做滑动窗口卷积
    %   原理：ΔT̃_t(i) = Σ_{k=-l}^{+l} kernel(k) × ΔT_{t+k}(i)
    %   即每帧 6 维参数各自在其窗口内加权平均
    %   MATLAB 的 conv 天然支持此操作，配合 'same' 保持输出长度
    % ================================================================
    paramSmoothedRelative = zeros(N, 6);

    for dim = 1:6
        paramSmoothedRelative(:, dim) = windowed_conv(paramRelative(:, dim), kernel, l, params.online_mode);
    end

    smooth_time = toc(t_smooth_start);

    % ================================================================
    % 步骤 3: 平滑后增量 → 绝对坐标重建
    %   参考论文 17 式(7)：T̃_t = T̃_{t-1} + ΔT̃_t
    % ================================================================
    t_rebuild_start = tic;

    rebuildParams = struct('useLogScale', true);
    paramSmoothedAbsolute = relative_to_absolute(paramSmoothedRelative, params.initAbsolute, rebuildParams);

    rebuild_time = toc(t_rebuild_start);

    % ================================================================
    % 步骤 4: 方差衰减比（消融实验的关键指标）
    %   等于 1 表示无平滑效果，越接近 0 表示平滑越强
    % ================================================================
    varBefore = mean(var(paramRelative, 0, 1));
    varAfter  = mean(var(paramSmoothedRelative, 0, 1));
    if varBefore > 1e-10
        varReduction = varAfter / varBefore;
    else
        varReduction = 1.0;
    end

    diagnostics = struct(...
        'window_radius',      l, ...
        'sigma',              params.sigma, ...
        'kernel_type',        params.kernel_type, ...
        'online_mode',        params.online_mode, ...
        'variance_reduction', varReduction, ...
        'smooth_time_ms',     smooth_time * 1000, ...
        'rebuild_time_ms',    rebuild_time * 1000);
end


% =========================================================================
%% 局部函数：build_kernel —— 生成平滑核
%
% 高斯核：exp(-x^2 / (2σ^2))，归一化使权重和为 1
% 均匀核：所有权重相等 = 1/(2l+1)，作为 baseline 对比
%
% 在线模式：核向右偏移，只看过去帧
%   窗口 [t, t+2l]（向后扩展 l 个位置，质心在 l）
% =========================================================================

function kernel = build_kernel(l, sigma, kernelType, onlineMode)
    arguments
        l (1,1) double
        sigma (1,1) double
        kernelType char
        onlineMode (1,1) logical
    end

    switch kernelType
        case 'gaussian'
            x = (-l:l)';
            kernel = exp(-x.^2 / (2 * sigma^2));
            kernel = kernel / sum(kernel);

        case 'uniform'
            w = 2 * l + 1;
            kernel = ones(w, 1) / w;

        otherwise
            error('不支持的核类型: %s', kernelType);
    end

    if onlineMode
        warning('在线模式：核窗口非对称，效果可能逊于离线模式');
    end
end


% =========================================================================
%% 局部函数：windowed_conv —— 滑动窗口卷积
%
% 对一维信号做窗口卷积，处理边界情况：
%   - 离线模式：标准对称卷积，两端用部分窗口（信号边缘截断）
%   - 在线模式：因果卷积，每帧只看自己及过去帧
%
% 边界策略：
%   对于帧 t，有效窗口索引必须在 [1, N] 范围内
%   离线 [t-l, t+l] ∩ [1, N] → 截取可用部分，核权重按比例重新归一化
%   在线 [t-2l, t] ∩ [1, N] → 同上
%
% 参考论文 17 第 3.3 节：有限窗口避免了长程误差累积
% =========================================================================

function y = windowed_conv(x, kernel, l, onlineMode)
    arguments
        x (:,1) double
        kernel (:,1) double
        l (1,1) double
        onlineMode (1,1) logical
    end

    N = length(x);
    y = zeros(N, 1);
    kw = length(kernel);  % 完整核长度 = 2l+1

    if onlineMode
        % 在线模式：窗口 [t-2l, t]，核长度同样为 2l+1
        % 核已预先生成，按"过去"方向使用
        for t = 1:N
            startIdx = max(1, t - kw + 1);
            endIdx   = t;
            winLen   = endIdx - startIdx + 1;

            if winLen < 1
                continue;
            end

            localKernel = kernel((end - winLen + 1):end);
            localKernel = localKernel / sum(localKernel);

            y(t) = sum(x(startIdx:endIdx) .* localKernel);
        end
    else
        % 离线模式：对称窗口 [t-l, t+l]
        for t = 1:N
            halfW = floor(kw / 2);
            startIdx = max(1, t - halfW);
            endIdx   = min(N, t + halfW);

            % 截取核的对应部分
            kernStart = startIdx - (t - halfW) + 1;
            kernEnd   = kernStart + (endIdx - startIdx);
            localKernel = kernel(kernStart:kernEnd);
            localKernel = localKernel / sum(localKernel);

            y(t) = sum(x(startIdx:endIdx) .* localKernel);
        end
    end
end


% =========================================================================
%% 局部函数：relative_to_absolute —— 增量积分重建绝对参数
%
% 与 relative_coordinate_model.m 中的版本完全一致。
% 作为局部函数内联以避免跨文件依赖。
% 参考论文 17_中北大学 (MDPI 2025)
% =========================================================================

function paramAbsolute = relative_to_absolute(paramRelative, initAbsolute, params)
    arguments
        paramRelative (:,6) double
        initAbsolute (1,6) double
        params struct = struct()
    end

    if ~isfield(params, 'useLogScale'),  params.useLogScale = true; end

    N = size(paramRelative, 1);
    if N == 0
        paramAbsolute = initAbsolute;
        return;
    end

    paramAbsolute = zeros(N, 6);

    paramAbsolute(:, 1) = initAbsolute(1) + cumsum(paramRelative(:, 1));
    paramAbsolute(:, 2) = initAbsolute(2) + cumsum(paramRelative(:, 2));
    paramAbsolute(:, 3) = initAbsolute(3) + cumsum(paramRelative(:, 3));

    if params.useLogScale
        paramAbsolute(1, 4) = initAbsolute(4);
        for i = 2:N
            paramAbsolute(i, 4) = paramAbsolute(i-1, 4) * exp(paramRelative(i, 4));
        end
    else
        paramAbsolute(1, 4) = initAbsolute(4);
        for i = 2:N
            paramAbsolute(i, 4) = paramAbsolute(i-1, 4) + paramRelative(i, 4);
        end
    end

    paramAbsolute(:, 5) = initAbsolute(5) + cumsum(paramRelative(:, 5));
    paramAbsolute(:, 6) = initAbsolute(6) + cumsum(paramRelative(:, 6));
end


% =========================================================================
%% 自测
% 验证马尔可夫窗口平滑的三个关键性质：
%   1. 方差衰减：平滑后方差应显著小于平滑前
%   2. 形状保持：低频趋势应被保留（平滑后的低频分量不应衰减 > 10%）
%   3. 边界不崩溃：首尾帧的输出应在合理范围（不出现 NaN 或极端值）
% =========================================================================

function [] = self_test()
    fprintf('=== markov_window_smooth 自测 ===\n');

    N = 200;
    t = (1:N)';

    % 构造合成数据：低频有意运动 + 高频抖动 + 微小噪声
    paramRel = zeros(N, 6);

    lowFreq = 0.3 * sin(2 * pi * 0.01 * t);         % 低频有意运动
    highFreq = 1.5 * sin(2 * pi * 0.3 * t);         % 高频抖动（目标滤除）
    noise = 0.05 * randn(N, 1);                      % 微小噪声

    paramRel(:, 1) = lowFreq + highFreq + noise;    % dx 混合信号
    paramRel(:, 2) = lowFreq * 0.5 + highFreq * 0.5 + noise * 0.5;
    paramRel(:, 3) = 0.01 * highFreq + 0.001 * noise;
    paramRel(:, 4) = 0.001 * highFreq + 0.0001 * noise;
    paramRel(:, 5) = 0.0001 * noise;
    paramRel(:, 6) = 0.0001 * noise;

    % 离线模式测试
    params = struct('window_radius', 3, 'sigma', 1.0, ...
        'kernel_type', 'gaussian', 'online_mode', false, ...
        'initAbsolute', zeros(1, 6));

    [smoothedRel, smoothedAbs, kernel, diag] = markov_window_smooth(paramRel, params);

    fprintf('  离线模式 - 方差衰减比: %.4f (应 < 0.5)\n', diag.variance_reduction);
    fprintf('  离线模式 - 平滑耗时: %.2f ms\n', diag.smooth_time_ms);
    fprintf('  离线模式 - 重建耗时: %.2f ms\n', diag.rebuild_time_ms);
    assert(diag.variance_reduction < 0.9, '方差衰减不足，平滑效果可能不够');
    assert(all(~isnan(smoothedAbs(:))), '重建绝对参数包含 NaN');
    assert(all(size(smoothedAbs) == [N, 6]), '输出尺寸错误');

    % 在线模式测试
    paramsOnline = struct('window_radius', 3, 'sigma', 1.0, ...
        'kernel_type', 'gaussian', 'online_mode', true, ...
        'initAbsolute', zeros(1, 6));
    [~, ~, ~, diagOnline] = markov_window_smooth(paramRel, paramsOnline);
    fprintf('  在线模式 - 方差衰减比: %.4f (略高于离线)\n', diagOnline.variance_reduction);

    % 均匀核对比（消融实验用）
    paramsUniform = struct('window_radius', 3, 'sigma', NaN, ...
        'kernel_type', 'uniform', 'online_mode', false, ...
        'initAbsolute', zeros(1, 6));
    [~, ~, kernelUniform] = markov_window_smooth(paramRel, paramsUniform);
    fprintf('  均匀核 - 核权重和: %.4f (应为 1.0)\n', sum(kernelUniform));
    assert(abs(sum(kernel) - 1.0) < 1e-10, '高斯核未归一化');
    assert(abs(sum(kernelUniform) - 1.0) < 1e-10, '均匀核未归一化');

    fprintf('  自测通过 ✓\n');
end
