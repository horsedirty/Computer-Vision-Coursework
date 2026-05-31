%% run_motion_smoothing.m —— 模块二主入口
% 编码规范：参见项目根目录 AGENTS.md
% 角色四 & 五共享接口
%
% 功能：串联仿射分解 → 相对坐标建模 → 平滑的完整流程。
% 接收模块一输出的变换矩阵序列，输出平滑后的变换矩阵序列。
%
% 三种平滑策略：
%   'markov'            - 完整版：相对坐标 + 马尔可夫窗口平滑（角色五实现）
%   'gaussian_relative' - 消融变体：相对坐标 + 高斯平滑（无窗口约束）
%   'gaussian_absolute' - 基线：绝对坐标直接高斯平滑（最朴素方案）
%
% 策略选择指南：
%   - markov: 区分"抖动"与"有意运动"的最佳方案，但计算复杂
%   - gaussian_relative: 消融实验用——去掉窗口约束，保留相对坐标
%   - gaussian_absolute: 最弱 baseline——直接平滑绝对轨迹，容易过度平滑有意运动
%
% INPUT:
%   T_sequence  - 3×3×N 数组，模块一输出的全局变换矩阵序列
%   params      - 参数字典
%     .decompose_params   - 传递给 decompose_affine_params 的参数
%     .relative_params    - 传递给 relative_coordinate_model 的参数
%     .smooth_params      - 传递给平滑子模块的参数
%     .smooth_strategy    - 'markov' | 'gaussian_absolute' | 'gaussian_relative'
%                           默认 'markov'（完整版）
%     .online_mode        - 是否在线模式（只看过去帧），默认 false
%
% OUTPUT:
%   T_smoothed  - 3×3×N 数组，平滑后的变换矩阵序列
%   paramHistory - N×6，平滑后的 6 参数序列（供轨迹可视化）
%   diagnostics - struct，各步骤耗时与统计
%
% 参考论文：17_在线拼接防抖 (MDPI 2025), 14_LightStab (CVPR 2026)

function [T_smoothed, paramHistory, diagnostics] = run_motion_smoothing(T_sequence, params)
    arguments
        T_sequence (:,:,:) double
        params struct = struct()
    end

    t_total = tic;
    N = size(T_sequence, 3);

    decompose_params = safeField(params, 'decompose_params', struct());
    relative_params  = safeField(params, 'relative_params', struct());
    smooth_params    = safeField(params, 'smooth_params', struct());
    smooth_strategy  = safeField(params, 'smooth_strategy', 'markov');
    online_mode      = safeField(params, 'online_mode', false);

    if N == 0
        error('变换矩阵序列为空');
    end
    if size(T_sequence, 1) ~= 3 || size(T_sequence, 2) ~= 3
        error('变换矩阵必须是 3×3×N 数组');
    end

    % ================================================================
    % 步骤 1: 仿射参数分解（角色四）
    % ================================================================
    t1 = tic;
    [paramAbsolute, decompDiag] = decompose_affine_params(T_sequence, decompose_params);
    decomp_time = toc(t1);

    % ================================================================
    % 步骤 2: 平滑
    % ================================================================
    t2 = tic;
    smoothDiag = struct();
    relDiag = struct();

    switch smooth_strategy
        case 'markov'
            [paramRelative, relDiag] = relative_coordinate_model(paramAbsolute, relative_params);
            smooth_params.initAbsolute = paramAbsolute(1, :);
            smooth_params.online_mode = online_mode;
            [~, paramHistory, ~, smoothDiag] = markov_window_smooth(paramRelative, smooth_params);

        case 'gaussian_relative'
            [paramRelative, relDiag] = relative_coordinate_model(paramAbsolute, relative_params);
            smooth_params.online_mode = online_mode;
            [paramRelSmoothed, smoothDiag] = gaussian_smooth(paramRelative, smooth_params);
            [paramHistory, rebuildDiag] = relative_to_absolute(paramRelSmoothed, paramAbsolute(1,:), struct());

        case 'gaussian_absolute'
            smooth_params.online_mode = online_mode;
            [paramHistory, smoothDiag] = gaussian_smooth(paramAbsolute, smooth_params);

        otherwise
            error('不支持的平滑策略: %s。可选: markov | gaussian_relative | gaussian_absolute', ...
                smooth_strategy);
    end

    smooth_time = toc(t2);

    % ================================================================
    % 步骤 3: 参数 → 变换矩阵重建（角色四）
    % ================================================================
    t3 = tic;
    T_smoothed = params_to_transforms(paramHistory);
    rebuild_time = toc(t3);

    total_time = toc(t_total);

    % ================================================================
    % 汇总诊断
    % ================================================================
    diagnostics = struct(...
        'decomp_time_ms',    decomp_time * 1000, ...
        'smooth_time_ms',    smooth_time * 1000, ...
        'rebuild_time_ms',   rebuild_time * 1000, ...
        'total_time_ms',     total_time * 1000, ...
        'smooth_strategy',   smooth_strategy, ...
        'frame_count',       N, ...
        'decomp_details',    decompDiag, ...
        'relative_details',  relDiag, ...
        'smooth_details',    smoothDiag);
end


%% 局部函数：params_to_transforms —— 6 参数序列 → 3×3×N 仿射变换矩阵
%
% 仿射矩阵分解：A_2x2 = R(θ) · S(s) · H(shx, shy)
%   其中 R = [cosθ  -sinθ;  sinθ  cosθ]   （旋转）
%        S = [s  0;  0  s]                （均匀缩放）
%        H = [1  shx;  shy  1]            （剪切）
%
% 合并得到：
%   a = s · (cosθ - sinθ·shy)
%   b = s · (cosθ·shx - sinθ)
%   c = s · (sinθ + cosθ·shy)
%   d = s · (sinθ·shx + cosθ)
%
% 参考论文 09_GlobalFlowNet 仿射分解思路
%
function T_seq = params_to_transforms(paramHistory)
    N = size(paramHistory, 1);
    T_seq = zeros(3, 3, N);

    for i = 1:N
        dx    = paramHistory(i, 1);
        dy    = paramHistory(i, 2);
        theta = paramHistory(i, 3);
        s     = max(paramHistory(i, 4), 1e-6);
        shx   = paramHistory(i, 5);
        shy   = paramHistory(i, 6);

        cos_t = cos(theta);
        sin_t = sin(theta);

        a = s * (cos_t - sin_t * shy);
        b = s * (cos_t * shx - sin_t);
        c = s * (sin_t + cos_t * shy);
        d = s * (sin_t * shx + cos_t);

        T_seq(:, :, i) = [a, b, dx;
                          c, d, dy;
                          0, 0,  1];
    end
end





%% 局部函数：safeField —— 安全读取 struct 字段
function val = safeField(s, fieldname, default)
    if isfield(s, fieldname)
        val = s.(fieldname);
    else
        val = default;
    end
end


function [paramAbsolute, diagnostics] = relative_to_absolute(paramRelative, initAbsolute, params)
    arguments
        paramRelative (:,6) double
        initAbsolute (1,6) double = zeros(1,6)
        params struct = struct()
    end

    N = size(paramRelative, 1);
    paramAbsolute = zeros(N, 6);

    cumDx = initAbsolute(1) + cumsum(paramRelative(:, 1));
    cumDy = initAbsolute(2) + cumsum(paramRelative(:, 2));
    cumTheta = initAbsolute(3) + cumsum(paramRelative(:, 3));
    cumScale = initAbsolute(4) * exp(cumsum(paramRelative(:, 4)));
    cumShx = initAbsolute(5) + cumsum(paramRelative(:, 5));
    cumShy = initAbsolute(6) + cumsum(paramRelative(:, 6));

    paramAbsolute(:, 1) = cumDx;
    paramAbsolute(:, 2) = cumDy;
    paramAbsolute(:, 3) = cumTheta;
    paramAbsolute(:, 4) = cumScale;
    paramAbsolute(:, 5) = cumShx;
    paramAbsolute(:, 6) = cumShy;

    diagnostics = struct(...
        'init_dx', initAbsolute(1), ...
        'init_dy', initAbsolute(2), ...
        'init_theta', initAbsolute(3), ...
        'init_scale', initAbsolute(4), ...
        'final_dx', cumDx(end), ...
        'final_dy', cumDy(end), ...
        'final_theta', cumTheta(end), ...
        'final_scale', cumScale(end), ...
        'max_cumulative_translation', max(hypot(cumDx, cumDy)));
end


%% 自测
% 验证三种策略的完整链路（分解→平滑→重建）
% fprintf('=== run_motion_smoothing 自测 ===\n');
% N_test = 30;
% T_raw = zeros(3, 3, N_test);
% T_raw(:,:,1) = eye(3);
% for i = 2:N_test
%     theta_i = 0.03 + 0.02*randn;
%     s_i     = 1.0 + 0.003*randn;
%     dx_i    = 3 + 1.5*randn;
%     dy_i    = 2 + 1.0*randn;
%     cos_t = cos(theta_i); sin_t = sin(theta_i);
%     T_raw(:,:,i) = [cos_t, -sin_t, dx_i; sin_t, cos_t, dy_i; 0, 0, 1];
% end
%
% strategies = {'gaussian_absolute', 'gaussian_relative', 'markov'};
% for s = 1:3
%     strat = strategies{s};
%     try
%         params_test = struct('smooth_strategy', strat, ...
%             'smooth_params', struct('sigma', 3, 'method', 'gaussian'));
%         [T_sm, paramHist, diag] = run_motion_smoothing(T_raw, params_test);
%         fprintf('  %-20s: 总耗时 %.1f ms | 输出 %d 帧\n', ...
%             strat, diag.total_time_ms, diag.frame_count);
%         assert(size(T_sm, 3) == N_test, '输出帧数不匹配');
%     catch ME
%         if strcmp(strat, 'markov')
%             fprintf('  %-20s: 跳过（角色五尚未实现）\n', strat);
%         else
%             rethrow(ME);
%         end
%     end
% end
% fprintf('run_motion_smoothing 自测通过\n\n');
