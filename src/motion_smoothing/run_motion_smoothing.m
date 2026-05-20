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


%% 辅助函数：6 参数序列 → 3×3×N 变换矩阵
function T_seq = params_to_transforms(paramHistory, H, W)
    N = size(paramHistory, 1);
    T_seq = zeros(3, 3, N);
    for i = 1:N
        dx    = paramHistory(i, 1);
        dy    = paramHistory(i, 2);
        theta = paramHistory(i, 3);
        s     = paramHistory(i, 4);
        shx   = paramHistory(i, 5);
        shy   = paramHistory(i, 6);

        % TODO: 从 6 参数合成 3×3 仿射矩阵
        % 旋转+缩放矩阵: R = s * [cos(theta) -sin(theta); sin(theta) cos(theta)]
        % 剪切矩阵:     SH = [1 shx; shy 1]
        % 完整仿射:     A = R * SH
        % T_seq(:,:,i) = [A(1,1) A(1,2) dx; A(2,1) A(2,2) dy; 0 0 1];

        cos_t = cos(theta);
        sin_t = sin(theta);
        T_seq(:,:,i) = [s*cos_t, -s*sin_t + shx, dx;
                        s*sin_t,  s*cos_t + shy, dy;
                        0,        0,              1];
    end
end


function val = safeField(s, fieldname, default)
    if isfield(s, fieldname)
        val = s.(fieldname);
    else
        val = default;
    end
end
