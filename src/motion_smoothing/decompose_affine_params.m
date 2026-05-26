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
%   theta = atan2(c, a)    （旋转角，弧度）
%   s    = sqrt(a² + c²)   （整体缩放比，无单位）
%   shx  = b + c           （水平剪切，逆推自前向模型）
%   shy  = d - a           （垂直剪切，逆推自前向模型）
%
% 分解与重建的数学一致性（参考 params_to_transforms 前向模型）：
%   前向: T = [s*cosθ, -s*sinθ+shx, dx; s*sinθ, s*cosθ+shy, dy; 0,0,1]
%   逆推: θ=atan2(c,a), s=√(a²+c²), shx=b+c, shy=d-a
%   重建: T' = params_to_transforms(decompose(T)) ≈ T（Frobenius 范数差 < 1e-10）
%
% INPUT:
%   T_sequence  - 3×3×N 数组，N 帧每帧的全局变换矩阵
%   params      - 参数字典
%     .normalize         - 是否对平移做归一化（除以帧对角长度），默认 false
%     .verify_reconstruction - 是否验证分解→重建一致性，默认 true
%
% OUTPUT:
%   paramTable  - N×6 double 矩阵，列: [dx, dy, theta, s, shx, shy]
%                 第一帧恒为 [0 0 0 1 0 0]（单位变换）
%   diagnostics - struct
%     .drift_total       - 累积平移总量（像素）
%     .max_rotation      - 最大帧间旋转角（度）
%     .mean_scale        - 平均缩放比
%     .recon_error       - 分解→重建的最大 Frobenius 范数误差
%     .projection_count  - 被规范化的投影矩阵数量
%
% 参考论文：17_在线拼接防抖 (MDPI 2025), 14_LightStab (CVPR 2026)
%
% TODO:
%   [x] 实现从 3×3 矩阵提取 6 参数的解析公式
%   [x] 验证提取正确性：用提取的参数重新合成 T'，对比 T' 与原始 T 的 Frobenius 范数差
%   [x] 处理投影变换退化情况（第 3 行 ≠ [0 0 1]）——先提取仿射子矩阵
%   [x] 绘制 6 参数的时间曲线（在可视化模块中完成）

function [paramTable, diagnostics] = decompose_affine_params(T_sequence, params)
    arguments
        T_sequence (:,:,:) double
        params struct = struct()
    end

    if ~isfield(params, 'normalize'),              params.normalize = false; end
    if ~isfield(params, 'verify_reconstruction'),  params.verify_reconstruction = true; end

    N = size(T_sequence, 3);
    if N == 0
        error('变换矩阵序列为空');
    end
    if size(T_sequence, 1) ~= 3 || size(T_sequence, 2) ~= 3
        error('变换矩阵必须是 3×3×N 数组, 当前为 %d×%d×%d', ...
            size(T_sequence, 1), size(T_sequence, 2), N);
    end

    paramArray = zeros(N, 6);
    projectionCount = 0;

    for i = 1:N
        T = T_sequence(:,:,i);

        if abs(T(3,1)) > 1e-10 || abs(T(3,2)) > 1e-10 || abs(T(3,3) - 1) > 1e-10
            T = T ./ T(3,3);
            projectionCount = projectionCount + 1;
        end

        a  = T(1,1);  b  = T(1,2);
        c  = T(2,1);  d  = T(2,2);
        tx = T(1,3);  ty = T(2,3);

        paramArray(i, 1) = tx;
        paramArray(i, 2) = ty;
        paramArray(i, 3) = atan2(c, a);
        paramArray(i, 4) = sqrt(a*a + c*c);
        paramArray(i, 5) = b + c;
        paramArray(i, 6) = d - a;
    end

    if params.normalize
        diagPixel = hypot(size(T_sequence, 1), size(T_sequence, 2));
        paramArray(:, 1:2) = paramArray(:, 1:2) ./ diagPixel;
    end

    paramTable = paramArray;

    reconError = 0;
    if params.verify_reconstruction
        T_recon = params_to_transforms_standalone(paramArray, 1, 1);
        reconError = max(vecnorm(reshape(T_recon - T_sequence, 9, N), 2, 1));
    end

    diagnostics = struct(...
        'drift_total',   hypot(paramArray(N,1), paramArray(N,2)), ...
        'max_rotation_deg', rad2deg(max(abs(paramArray(:,3)))), ...
        'mean_scale',    mean(paramArray(:,4)), ...
        'recon_error',   reconError, ...
        'projection_count', projectionCount, ...
        'frame_count',   N);
end


function T_seq = params_to_transforms_standalone(paramHistory, H, W)
    N = size(paramHistory, 1);
    T_seq = zeros(3, 3, N);
    for i = 1:N
        dx    = paramHistory(i, 1);
        dy    = paramHistory(i, 2);
        theta = paramHistory(i, 3);
        s     = paramHistory(i, 4);
        shx   = paramHistory(i, 5);
        shy   = paramHistory(i, 6);

        cos_t = cos(theta);
        sin_t = sin(theta);
        T_seq(:,:,i) = [s*cos_t, -s*sin_t + shx, dx;
                        s*sin_t,  s*cos_t + shy, dy;
                        0,        0,              1];
    end
end


%% 自测
% 验证分解→重建一致性
% fprintf('=== decompose_affine_params 自测 ===\n');
% N_test = 20;
% T_test = zeros(3, 3, N_test);
% for i = 1:N_test
%     theta = 0.05 * i + 0.01 * randn;
%     s     = 1.0 + 0.005 * i + 0.001 * randn;
%     shx   = 0.01 * randn;
%     shy   = 0.01 * randn;
%     dx    = 3 * i + randn;
%     dy    = 2 * i + randn;
%     cos_t = cos(theta); sin_t = sin(theta);
%     T_test(:,:,i) = [s*cos_t, -s*sin_t+shx, dx;
%                      s*sin_t,  s*cos_t+shy, dy;
%                      0,        0,            1];
% end
% [paramOut, diag] = decompose_affine_params(T_test);
% assert(diag.recon_error < 1e-10, '重建误差过大: %e', diag.recon_error);
% fprintf('  重建误差: %.2e (应接近 0)\n', diag.recon_error);
% fprintf('  漂移总量: %.1f px\n', diag.drift_total);
% fprintf('  最大旋转: %.1f deg\n', diag.max_rotation_deg);
% fprintf('  平均缩放: %.3f\n', diag.mean_scale);
% fprintf('  投影计数: %d (预期 0)\n', diag.projection_count);
% fprintf('decompose_affine_params 自测通过\n\n');
