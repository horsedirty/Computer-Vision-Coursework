%% compute_stabilization_ratio.m —— 评估指标：稳定比 SR
% 编码规范：参见项目根目录 AGENTS.md
% 角色八负责实现
%
% 功能：计算稳定比 (Stabilization Ratio, SR)。
% SR = 稳定后帧间运动量均值 / 原始帧间运动量均值
% SR < 1 表示有稳定效果，越小越好。
%
% 帧间运动量的定义：全局变换矩阵中平移分量的模长 ||(dx, dy)||
%
% INPUT:
%   T_raw_seq       - 3×3×N，原始变换矩阵序列（模块一输出）
%   T_smoothed_seq  - 3×3×N，平滑后变换矩阵序列（模块二输出）
%   params          - 参数字典
%     .use_full_norm - 是否使用 Frobenius 范数（含旋转缩放），默认 false（只用平移）
%
% OUTPUT:
%   SR              - 稳定比，标量 (0 到 1 之间，越小越好)
%   motion_raw      - (N-1)×1，原始帧间运动量序列
%   motion_smoothed - (N-1)×1，平滑后帧间运动量序列
%   diagnostics     - struct，含各统计量

function [SR, motion_raw, motion_smoothed, diagnostics] = compute_stabilization_ratio(T_raw_seq, T_smoothed_seq, params)
    arguments
        T_raw_seq (:,:,:) double
        T_smoothed_seq (:,:,:) double
        params struct = struct()
    end

    if ~isfield(params, 'use_full_norm'), params.use_full_norm = false; end

    N = size(T_raw_seq, 3);
    if N < 2
        error('需要至少 2 帧');
    end

    motion_raw = zeros(N-1, 1);
    motion_smoothed = zeros(N-1, 1);

    for i = 1:N-1
        if params.use_full_norm
            % 使用 Frobenius 范数（含旋转、缩放、平移）
            motion_raw(i)      = norm(T_raw_seq(:,:,i+1) - T_raw_seq(:,:,i), 'fro');
            motion_smoothed(i) = norm(T_smoothed_seq(:,:,i+1) - T_smoothed_seq(:,:,i), 'fro');
        else
            % 仅平移分量
            dx_raw = T_raw_seq(1,3,i+1) - T_raw_seq(1,3,i);
            dy_raw = T_raw_seq(2,3,i+1) - T_raw_seq(2,3,i);
            motion_raw(i) = sqrt(dx_raw^2 + dy_raw^2);

            dx_sm = T_smoothed_seq(1,3,i+1) - T_smoothed_seq(1,3,i);
            dy_sm = T_smoothed_seq(2,3,i+1) - T_smoothed_seq(2,3,i);
            motion_smoothed(i) = sqrt(dx_sm^2 + dy_sm^2);
        end
    end

    mean_raw = mean(motion_raw);
    mean_sm  = mean(motion_smoothed);

    if mean_raw < 1e-10
        warning('原始运动量接近于 0，SR 不可靠');
        SR = NaN;
    else
        SR = mean_sm / mean_raw;
    end

    diagnostics = struct(...
        'mean_motion_raw', mean_raw, ...
        'mean_motion_smoothed', mean_sm, ...
        'std_motion_raw', std(motion_raw), ...
        'std_motion_smoothed', std(motion_smoothed), ...
        'use_full_norm', params.use_full_norm);
end
