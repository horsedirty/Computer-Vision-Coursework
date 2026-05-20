%% relative_coordinate_model.m —— 相对坐标建模
% 编码规范：参见项目根目录 AGENTS.md
% 角色五负责实现
%
% 功能：将绝对坐标下的仿射参数序列转换为相对坐标（帧间增量）。
% 这是抑制长序列累积误差的关键——平滑作用于增量序列而非绝对轨迹。
%
% 数学背景（参考论文 17_中北大学在线拼接防抖）：
%   绝对坐标：     T_t     = [第 t 帧在绝对坐标系中的变换参数]
%   相对坐标增量： ΔT_t    = T_t - T_{t-1}  （帧间增量）
%   平滑后增量：   ΔT̃_t    = smooth(ΔT_{t-l}, ..., ΔT_{t+l})  （窗口平滑）
%   重建绝对坐标： T̃_t     = T̃_{t-1} + ΔT̃_t  （增量积分）
%
% INPUT:
%   paramAbsolute - N×6，绝对坐标下的仿射参数序列
%   params        - 参数字典
%     .useLogScale    - 对缩放分量使用对数域（乘法变加法），默认 true
%     .wrapRotation   - 对旋转角做相位展开（unwrap），默认 true
%
% OUTPUT:
%   paramRelative - N×6，相对坐标下的增量序列
%   diagnostics   - struct，增量统计信息
%
% TODO:
%   [ ] 实现 paramAbsolute → paramRelative 的差分转换
%   [ ] 对旋转角做 unwrap（处理 ±π 跳变）
%   [ ] 对缩放分量使用 log 域（s_rel = log(s_t / s_{t-1})）
%   [ ] 验证转换可逆性：relToAbs(absToRel(x)) ≈ x
%   [ ] 绘制增量序列的时间曲线，观察抖动成分（高频振荡）与运动成分（趋势）

function [paramRelative, diagnostics] = relative_coordinate_model(paramAbsolute, params)
    arguments
        paramAbsolute (:,6) double
        params struct = struct()
    end

    if ~isfield(params, 'useLogScale'),   params.useLogScale = true; end
    if ~isfield(params, 'wrapRotation'),  params.wrapRotation = true; end

    N = size(paramAbsolute, 1);
    paramRelative = zeros(N, 6);

    % idx: 1=dx, 2=dy, 3=theta, 4=scale, 5=shx, 6=shy

    % === 平移分量：直接差分 ===
    % Δdx_t = dx_t - dx_{t-1}
    paramRelative(2:end, 1:2) = diff(paramAbsolute(:, 1:2));

    % === 旋转分量：相位展开后差分 ===
    if params.wrapRotation
        theta_unwrapped = unwrap(paramAbsolute(:, 3));
        paramRelative(2:end, 3) = diff(theta_unwrapped);
    else
        paramRelative(2:end, 3) = diff(paramAbsolute(:, 3));
    end

    % === 缩放分量：对数域差分（乘法→加法） ===
    if params.useLogScale
        logScale = log(max(paramAbsolute(:, 4), 1e-6));  % 防 log(0)
        paramRelative(2:end, 4) = diff(logScale);
    else
        paramRelative(2:end, 4) = diff(paramAbsolute(:, 4));
    end

    % === 剪切分量（通常变化很小） ===
    paramRelative(2:end, 5:6) = diff(paramAbsolute(:, 5:6));

    % === 诊断 ===
    diagnostics = struct(...
        'mean_delta_translation', mean(vecnorm(paramRelative(:,1:2), 2, 2)), ...
        'max_delta_translation',  max(vecnorm(paramRelative(:,1:2), 2, 2)), ...
        'std_delta_theta',        std(paramRelative(:,3)));
end


% =========================================================================
%% 逆转换：相对坐标 → 绝对坐标（供平滑后重建使用）
% =========================================================================

function [paramAbsolute] = relative_to_absolute(paramRelative, initAbsolute, params)
    % TODO: 实现增量积分重建绝对坐标
    % T̃_t = T̃_{t-1} + ΔT̃_t
    % 旋转分量需要 cumsum(unwrapped_delta)
    % 缩放分量需要 exp(cumsum(log_delta)) 再乘以初始值
    arguments
        paramRelative (:,6) double
        initAbsolute (1,6) double  % 第一帧的绝对参数（作为积分起点）
        params struct = struct()
    end

    N = size(paramRelative, 1);
    paramAbsolute = zeros(N, 6);

    % 平移：cumsum
    paramAbsolute(:, 1) = initAbsolute(1) + cumsum(paramRelative(:, 1));
    paramAbsolute(:, 2) = initAbsolute(2) + cumsum(paramRelative(:, 2));

    % 旋转：cumsum（已在 unwrap 域）
    paramAbsolute(:, 3) = initAbsolute(3) + cumsum(paramRelative(:, 3));

    % 缩放：exp(cumsum) × 初始值
    paramAbsolute(:, 4) = initAbsolute(4) * exp(cumsum(paramRelative(:, 4)));

    % 剪切：cumsum
    paramAbsolute(:, 5) = initAbsolute(5) + cumsum(paramRelative(:, 5));
    paramAbsolute(:, 6) = initAbsolute(6) + cumsum(paramRelative(:, 6));
end
