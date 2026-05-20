%% visualize_trajectory.m —— 运动轨迹可视化
% 编码规范：参见项目根目录 AGENTS.md
% 角色八负责实现
%
% 功能：绘制原始相机累积运动轨迹 vs 平滑后轨迹的对比图。
% 这是证明「保留了物体真实运动」最直观的可视化证据。
%
% INPUT:
%   T_raw_seq       - 3×3×N，原始变换矩阵
%   T_smoothed_seq  - 3×3×N，平滑后变换矩阵
%   params          - 参数字典
%     .savePath       - 保存路径（png），默认 '' 不保存
%     .title          - 图标题
%     .showLegend     - 是否显示图例，默认 true
%     .downsample     - 降采样因子（轨迹点太多时），默认 1
%
% OUTPUT:
%   figHandle   - figure 句柄
%   traj_raw    - N×2，累积原始轨迹 [cumX, cumY]
%   traj_smoothed - N×2，累积平滑轨迹

function [figHandle, traj_raw, traj_smoothed] = visualize_trajectory(T_raw_seq, T_smoothed_seq, params)
    arguments
        T_raw_seq (:,:,:) double
        T_smoothed_seq (:,:,:) double
        params struct = struct()
    end

    if ~isfield(params, 'savePath'),    params.savePath = ''; end
    if ~isfield(params, 'title'),       params.title = '累积运动轨迹对比'; end
    if ~isfield(params, 'showLegend'),  params.showLegend = true; end
    if ~isfield(params, 'downsample'),  params.downsample = 1; end

    N = size(T_raw_seq, 3);

    % === 累积平移量 ===
    traj_raw = zeros(N, 2);
    traj_smoothed = zeros(N, 2);

    % 初始位置为原点
    cumX_raw = 0; cumY_raw = 0;
    cumX_sm = 0;  cumY_sm = 0;

    traj_raw(1,:) = [0, 0];
    traj_smoothed(1,:) = [0, 0];

    for i = 2:N
        % 原始
        cumX_raw = cumX_raw + T_raw_seq(1,3,i) - T_raw_seq(1,3,i-1);
        cumY_raw = cumY_raw + T_raw_seq(2,3,i) - T_raw_seq(2,3,i-1);
        traj_raw(i,:) = [cumX_raw, cumY_raw];

        % 平滑后
        cumX_sm = cumX_sm + T_smoothed_seq(1,3,i) - T_smoothed_seq(1,3,i-1);
        cumY_sm = cumY_sm + T_smoothed_seq(2,3,i) - T_smoothed_seq(2,3,i-1);
        traj_smoothed(i,:) = [cumX_sm, cumY_sm];
    end

    % === 降采样 ===
    ds = params.downsample;
    if ds > 1
        idx = 1:ds:N;
        traj_raw_plot = traj_raw(idx, :);
        traj_sm_plot  = traj_smoothed(idx, :);
    else
        traj_raw_plot = traj_raw;
        traj_sm_plot  = traj_smoothed;
    end

    % === 绘图 ===
    figHandle = figure('Name', params.title, 'NumberTitle', 'off');
    hold on;
    plot(traj_raw_plot(:,1), traj_raw_plot(:,2), 'r-', 'LineWidth', 1.2, ...
        'DisplayName', '原始轨迹（含抖动）');
    plot(traj_sm_plot(:,1), traj_sm_plot(:,2), 'b-', 'LineWidth', 1.5, ...
        'DisplayName', '平滑后轨迹');
    hold off;

    xlabel('累积水平位移 (像素)');
    ylabel('累积垂直位移 (像素)');
    title(params.title);
    if params.showLegend
        legend('Location', 'best');
    end
    axis equal;
    grid on;

    % === 保存 ===
    if ~isempty(params.savePath)
        saveas(figHandle, params.savePath);
        fprintf('轨迹图已保存: %s\n', params.savePath);
    end
end
