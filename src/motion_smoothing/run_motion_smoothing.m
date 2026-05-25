%% run_motion_smoothing.m —— 模块二主入口
% 编码规范：参见项目根目录 AGENTS.md
% 角色四 & 五共享接口
%
% 功能：串联仿射分解 → 相对坐标建模 → 窗口平滑的完整流程。
% 接收模块一输出的变换矩阵序列，输出平滑后的变换矩阵序列。
%
% INPUT:
%   T_sequence  - 3×3×N 数组，模块一输出的全局变换矩阵序列
%   params      - 参数字典
%     .decompose_params   - 传递给 decompose_affine_params 的参数
%     .relative_params    - 传递给 relative_coordinate_model 的参数
%     .smooth_params      - 传递给 markov_window_smooth 的参数
%     .smooth_strategy    - 'markov' | 'gaussian_absolute' | 'gaussian_relative'
%                           默认 'markov'（完整版）
%     .online_mode        - 是否在线模式（只看过去帧），默认 false
%
% OUTPUT:
%   T_smoothed  - 3×3×N 数组，平滑后的变换矩阵序列
%   paramHistory - N×6，平滑后的 6 参数序列（供轨迹可视化）
%   diagnostics - struct，各步骤耗时与统计
%
% 参考论文：17_在线拼接防抖 (MDPI 2025), 09_GlobalFlowNet, 15_微跳视 SO(3)

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

    % ================================================================
    % 步骤 1: 仿射参数分解（角色四）
    % ================================================================
    t1 = tic;
    [paramAbsolute, decompDiag] = decompose_affine_params(T_sequence, decompose_params);
    decomp_time = toc(t1);

    % ================================================================
    % 步骤 2: 平滑（角色五）
    % ================================================================
    t2 = tic;

    switch smooth_strategy
        case 'markov'
            % 完整版：相对坐标 + 马尔可夫窗口平滑
            [paramRelative, relDiag] = relative_coordinate_model(paramAbsolute, relative_params);
            smooth_params.initAbsolute = paramAbsolute(1, :);
            smooth_params.online_mode = online_mode;
            [~, paramHistory, ~, smoothDiag] = markov_window_smooth(paramRelative, smooth_params);

        case 'gaussian_relative'
            % 消融变体：相对坐标 + 高斯平滑（无窗口约束）
            [paramRelative, relDiag] = relative_coordinate_model(paramAbsolute, relative_params);
            [paramHistory, smoothDiag] = gaussian_smooth(paramRelative, smooth_params);
            % 重建绝对坐标
            paramHistory = relative_to_absolute(paramHistory, paramAbsolute(1,:), struct());

        case 'gaussian_absolute'
            % 基线：绝对坐标直接高斯平滑
            [paramHistory, smoothDiag] = gaussian_smooth(paramAbsolute, smooth_params);

        otherwise
            error('不支持的平滑策略: %s', smooth_strategy);
    end

    smooth_time = toc(t2);

    % ================================================================
    % 步骤 3: 参数 → 变换矩阵重建（角色四）
    % ================================================================
    t3 = tic;
    T_smoothed = params_to_transforms(paramHistory, size(T_sequence, 1), size(T_sequence, 2));
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
        'decomp_details',    decompDiag, ...
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
function T_seq = params_to_transforms(paramHistory, H, W)
    arguments
        paramHistory (:,6) double
        H (1,1) double
        W (1,1) double
    end

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


%% 局部函数：relative_to_absolute —— 增量积分重建绝对参数
%
% 与 relative_coordinate_model.m 中的版本完全一致。
% 作为局部函数内联以避免跨文件依赖。
% 参考论文 17_中北大学 (MDPI 2025)
%
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


%% 局部函数：safeField —— 安全读取 struct 字段
function val = safeField(s, fieldname, default)
    if isfield(s, fieldname)
        val = s.(fieldname);
    else
        val = default;
    end
end
