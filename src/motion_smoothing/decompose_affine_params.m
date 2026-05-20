%% decompose_affine_params.m —— 仿射变换参数分解
% 编码规范：参见项目根目录 AGENTS.md
% 角色四负责实现
%
% 功能：从 3×3 仿射/投影变换矩阵中提取 6 自由度仿射参数序列。
% 这一步是运动分解的基础——把"变换矩阵"翻译成可解释的物理运动参数。
%
% 背景：一个 2D 仿射变换可写为：
%   [x']   [a  b  tx] [x]
%   [y'] = [c  d  ty] [y]
%   [1 ]   [0  0   1] [1]
%
% 6 个自由度的物理含义：
%   dx   = tx              （水平平移，像素）
%   dy   = ty              （垂直平移，像素）
%   theta = atan2(-c, a)   （旋转角，弧度）
%   s    = sqrt(a² + c²)   （缩放比，无单位）
%   shx  = (a*b + c*d) / (a*d - b*c) 近似（水平剪切）
%   shy  = 可单独计算（垂直剪切）
%
% INPUT:
%   T_sequence  - 3×3×N 数组，N 帧每帧的全局变换矩阵
%   params      - 参数字典
%     .normalize  - 是否对平移做归一化（除以帧对角长度），默认 false
%
% OUTPUT:
%   paramTable  - N×6 timetable 或 double 矩阵，列: [dx, dy, theta, s, shx, shy]
%   diagnostics - struct
%     .drift_total    - 累积平移总量（像素）
%     .max_rotation   - 最大帧间旋转角（度）
%     .mean_scale     - 平均缩放比
%
% TODO:
%   [ ] 实现从 3×3 矩阵提取 6 参数的解析公式
%   [ ] 验证提取正确性：用提取的参数重新合成 T'，对比 T' 与原始 T 的 Frobenius 范数差
%   [ ] 处理投影变换退化情况（第 3 行 ≠ [0 0 1]）——先提取仿射子矩阵
%   [ ] 输出为 MATLAB timetable，以帧号为时间索引（便于后续 plot）
%   [ ] 绘制 6 参数的时间曲线，标注典型抖动模式（高频小幅 = 抖动，低频大幅 = 有意运镜）

function [paramTable, diagnostics] = decompose_affine_params(T_sequence, params)
    arguments
        T_sequence (:,:,:) double
        params struct = struct()
    end

    if ~isfield(params, 'normalize'), params.normalize = false; end

    N = size(T_sequence, 3);
    if N == 0
        error('变换矩阵序列为空');
    end

    % 预分配
    paramArray = zeros(N, 6);  % [dx, dy, theta, s, shx, shy]

    for i = 1:N
        T = T_sequence(:,:,i);

        % 确保仿射形式（第 3 行 = [0 0 1]）
        % 如果是投影变换（第 3 行 ≠ [0 0 1]），提取仿射子矩阵
        if abs(T(3,1)) > 1e-10 || abs(T(3,2)) > 1e-10 || abs(T(3,3) - 1) > 1e-10
            % TODO: 规范化投影矩阵，提取仿射近似
            % T(1:2, :) = T(1:2, :) ./ T(3,3);  % 简化的规范化
        end

        a  = T(1,1);  b  = T(1,2);
        c  = T(2,1);  d  = T(2,2);
        tx = T(1,3);  ty = T(2,3);

        % TODO: 提取 6 参数（以下为占位，用更精确的分解）
        paramArray(i, 1) = tx;                        % dx
        paramArray(i, 2) = ty;                        % dy
        paramArray(i, 3) = atan2(c, a);               % theta (rad)
        paramArray(i, 4) = sqrt(a*a + c*c);           % scale
        paramArray(i, 5) = 0;                         % shx (TODO: 正确公式)
        paramArray(i, 6) = 0;                         % shy (TODO: 正确公式)
    end

    % === 可选：平移归一化 ===
    if params.normalize
        % TODO: 除以 sqrt(H² + W²)
    end

    % === 输出为 timetable ===
    % TODO: paramTable = array2timetable(paramArray, 'RowTimes', seconds(1:N), ...
    %     'VariableNames', {'dx','dy','theta','scale','shx','shy'});
    paramTable = paramArray;

    % === 诊断 ===
    diagnostics = struct(...
        'drift_total',   sqrt(paramArray(N,1)^2 + paramArray(N,2)^2), ...
        'max_rotation',  rad2deg(max(abs(paramArray(:,3)))), ...
        'mean_scale',    mean(paramArray(:,4)));
end
