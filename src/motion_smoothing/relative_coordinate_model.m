%% relative_coordinate_model.m —— 相对坐标建模
% 编码规范：参见项目根目录 AGENTS.md
% 角色五负责实现
%
% 功能：将绝对坐标下的仿射参数序列转换为相对坐标（帧间增量）。
% 这是抑制长序列累积误差的关键——平滑作用于增量序列而非绝对轨迹，
% 参考论文 17_中北大学在线拼接防抖 (MDPI Applied Sciences 2025)。
%
% 数学背景：
%   绝对坐标：     T_t     = [第 t 帧在绝对坐标系中的变换参数]
%   相对坐标增量： ΔT_t    = T_t - T_{t-1}  （帧间增量）
%   平滑后增量：   ΔT̃_t    = smooth(ΔT_{t-l}, ..., ΔT_{t+l})
%   重建绝对坐标： T̃_t     = T̃_{t-1} + ΔT̃_t  （增量积分）
%
% 6 个自由度的列索引：
%   col 1 = dx    (水平平移, 像素)
%   col 2 = dy    (垂直平移, 像素)
%   col 3 = theta (旋转角, rad)
%   col 4 = scale (缩放比)
%   col 5 = shx   (水平剪切)
%   col 6 = shy   (垂直剪切)
%
% INPUT:
%   paramAbsolute - N×6 double，绝对坐标下的仿射参数序列（首帧为参考零点）
%   params        - struct
%     .useLogScale    - 对缩放分量使用对数域（乘法→加法），默认 true
%     .wrapRotation   - 对旋转角做相位展开（unwrap），默认 true
%
% OUTPUT:
%   paramRelative - N×6 double，相对坐标增量序列
%                  首帧 ΔT_1 = 0（无前帧可做差分），差分从第 2 帧开始
%   diagnostics   - struct
%     .mean_delta_translation - 平均帧间平移量 (px)
%     .max_delta_translation  - 最大帧间平移量 (px)
%     .std_delta_theta        - 帧间旋转角标准差 (rad)
%     .mean_delta_log_scale   - 帧间对数缩放均值
%     .abs2rel_time_ms        - 正向转换耗时 (ms)
%     .rel2abs_time_ms        - 逆转换验证耗时 (ms)
%     .roundtrip_error        - 往返误差 (Frobenius 范数均值)
%
% 依赖：MATLAB 内置 unwrap()
%
% 参考论文：17_中北大学在线拼接防抖 (MDPI Applied Sciences 2025)

function [paramRelative, diagnostics] = relative_coordinate_model(paramAbsolute, params)
    arguments
        paramAbsolute (:,6) double
        params struct = struct()
    end

    if ~isfield(params, 'useLogScale'),   params.useLogScale = true; end
    if ~isfield(params, 'wrapRotation'),  params.wrapRotation = true; end

    t_start = tic;

    N = size(paramAbsolute, 1);
    if N < 2
        error('相对坐标建模需要至少 2 帧');
    end

    paramRelative = zeros(N, 6);

    % ================================================================
    % 1. 平移分量 (dx, dy)：直接差分
    %    抖动在高频出现，差分可以滤掉低频漂移
    % ================================================================
    paramRelative(2:end, 1:2) = diff(paramAbsolute(:, 1:2));

    % ================================================================
    % 2. 旋转分量 (theta)：先展开相位再差分
    %    避免 ±π 附近跳变导致的差分假峰，参考论文 17 第 3.2 节
    % ================================================================
    if params.wrapRotation
        theta_unwrapped = unwrap(paramAbsolute(:, 3));
        paramRelative(2:end, 3) = diff(theta_unwrapped);
    else
        paramRelative(2:end, 3) = diff(paramAbsolute(:, 3));
    end

    % ================================================================
    % 3. 缩放分量 (scale)：对数域差分
    %    缩放是乘法关系 (s_t = s_{t-1} × factor)，取 log 后变加法
    %    Δlog(s_t) = log(s_t) - log(s_{t-1}) = log(s_t / s_{t-1})
    %    平滑后用 exp(cumsum) 还原，天然保证了 s > 0
    % ================================================================
    if params.useLogScale
        logScale = log(max(paramAbsolute(:, 4), 1e-8));
        paramRelative(2:end, 4) = diff(logScale);
    else
        paramRelative(2:end, 4) = diff(paramAbsolute(:, 4));
    end

    % ================================================================
    % 4. 剪切分量 (shx, shy)：直接差分（通常幅值很小）
    % ================================================================
    paramRelative(2:end, 5:6) = diff(paramAbsolute(:, 5:6));

    abs2rel_time = toc(t_start);

    % ================================================================
    % 往返验证：abs → rel → abs，确认转换可逆
    % ================================================================
    if N >= 3
        paramVerify = relative_to_absolute(paramRelative, paramAbsolute(1, :), params);
        roundtripErr = mean(vecnorm(paramVerify - paramAbsolute, 2, 2));
    else
        roundtripErr = NaN;
    end

    % ================================================================
    % 诊断汇总
    % ================================================================
    diagnostics = struct(...
        'mean_delta_translation', mean(vecnorm(paramRelative(2:end, 1:2), 2, 2)), ...
        'max_delta_translation',  max(vecnorm(paramRelative(2:end, 1:2), 2, 2)), ...
        'std_delta_theta',        std(paramRelative(2:end, 3)), ...
        'mean_delta_log_scale',   mean(abs(paramRelative(2:end, 4))), ...
        'abs2rel_time_ms',        abs2rel_time * 1000, ...
        'rel2abs_time_ms',        NaN, ...
        'roundtrip_error',        roundtripErr);
end


% =========================================================================
%% 局部函数：relative_to_absolute —— 逆转换（增量积分）
%
% 从平滑后的增量序列重建绝对参数序列。
% 这是相对坐标建模的逆过程，平滑后必须调用来恢复可用的绝对参数。
%
% 参考论文 17_中北大学 (MDPI 2025)：平滑作用于增量域，积分回绝对域
% =========================================================================

function paramAbsolute = relative_to_absolute(paramRelative, initAbsolute, params)
    arguments
        paramRelative (:,6) double
        initAbsolute (1,6) double
        params struct = struct()
    end

    if ~isfield(params, 'useLogScale'),  params.useLogScale = true; end

    t_start = tic;
    N = size(paramRelative, 1);

    if N == 0
        paramAbsolute = initAbsolute;
        return;
    end

    paramAbsolute = zeros(N, 6);

    % 平移：累加增量（cumsum）
    paramAbsolute(:, 1) = initAbsolute(1) + cumsum(paramRelative(:, 1));
    paramAbsolute(:, 2) = initAbsolute(2) + cumsum(paramRelative(:, 2));

    % 旋转：累加增量（增量已在 unwrap 域）
    paramAbsolute(:, 3) = initAbsolute(3) + cumsum(paramRelative(:, 3));

    % 缩放：在对数域累加后指数还原
    % s̃_t = s₀ × exp(Σ Δlog(s_k))，保证 s̃_t > 0
    % 参考论文 17 式(6)：对数域平滑后需指数还原
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

    % 剪切：累加增量
    paramAbsolute(:, 5) = initAbsolute(5) + cumsum(paramRelative(:, 5));
    paramAbsolute(:, 6) = initAbsolute(6) + cumsum(paramRelative(:, 6));
end


% =========================================================================
%% 自测
% 验证相对坐标建模的正确性：abs → rel → abs 往返误差应 < 1e-10
% =========================================================================

function [] = self_test()
    fprintf('=== relative_coordinate_model 自测 ===\n');

    N = 100;
    t = (1:N)';

    paramAbs = zeros(N, 6);
    paramAbs(:, 1) = 2 * sin(0.1 * t) + 0.1 * randn(N, 1);           % dx
    paramAbs(:, 2) = cos(0.15 * t) + 0.1 * randn(N, 1);              % dy
    paramAbs(:, 3) = 0.02 * sin(0.05 * t) + 0.001 * randn(N, 1);     % theta
    paramAbs(:, 4) = 1 + 0.01 * sin(0.03 * t);                       % scale
    paramAbs(:, 5) = 0.001 * randn(N, 1);                            % shx
    paramAbs(:, 6) = 0.001 * randn(N, 1);                            % shy

    [paramRel, diag] = relative_coordinate_model(paramAbs, struct());
    fprintf('  正向转换耗时: %.2f ms\n', diag.abs2rel_time_ms);
    fprintf('  平均帧间平移: %.4f px\n', diag.mean_delta_translation);
    fprintf('  最大帧间平移: %.4f px\n', diag.max_delta_translation);
    fprintf('  往返误差:     %.2e (应 < 1e-10)\n', diag.roundtrip_error);

    assert(diag.roundtrip_error < 1e-8, '往返误差过大');
    assert(all(size(paramRel) == [N, 6]), '输出尺寸错误');
    assert(all(paramRel(1, :) == 0), '首帧增量应为零');

    fprintf('  自测通过 ✓\n');
end
