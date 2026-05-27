%% visualize_module_pie.m —— Three-Module Time Pie Chart Visualization
% Coding standard: See project root AGENTS.md
% Role 8 is responsible for implementation
%
% Function: Extract average time of motion estimation, smoothing, and frame
% synthesis modules from ablation experiment results table, generate a pie
% chart to visually show each module's proportion of total time.
%
% INPUT:
%   resultsTable   - table from run_ablation_study output
%                     Must contain columns: Experiment, MotionEst_ms, Smoothing_ms, Synthesis_ms
%   params         - parameter struct
%     .savePath      - save path, default ''
%     .title         - chart title, default 'Module Time Distribution'
%     .experimentIdx - experiment index to plot, default 1 (baseline)
%
% OUTPUT:
%   figHandle      - figure handle

function figHandle = visualize_module_pie(resultsTable, params)
    arguments
        resultsTable table
        params struct = struct()
    end

    if ~isfield(params, 'savePath'),       params.savePath = ''; end
    if ~isfield(params, 'title'),          params.title = 'Module Time Distribution'; end
    if ~isfield(params, 'experimentIdx'),  params.experimentIdx = 1; end

    idx = params.experimentIdx;
    if idx > height(resultsTable)
        error('实验索引 %d 超出表格行数 %d', idx, height(resultsTable));
    end

    % 提取三模块耗时 (ms)
    times = [resultsTable.MotionEst_ms(idx), ...
             resultsTable.Smoothing_ms(idx), ...
             resultsTable.Synthesis_ms(idx)];
    labels = {'Motion Estimation', 'Trajectory Smoothing', 'Frame Synthesis & Deblurring'};

    % 过滤 NaN
    validMask = ~isnan(times) & times > 0;
    if ~any(validMask)
        warning('所选实验无有效耗时数据');
        figHandle = figure('Visible', 'off');
        return;
    end
    times = times(validMask);
    labels = labels(validMask);

    % 构建颜色映射（论文常用色）
    colors = [0.2 0.6 0.9;   % 蓝 - 运动估计
              0.9 0.4 0.2;   % 橙 - 平滑
              0.2 0.8 0.4];  % 绿 - 帧合成
    colors = colors(validMask, :);

    % 创建饼图
    figHandle = figure('Name', params.title, 'NumberTitle', 'off', ...
        'Position', [200, 200, 600, 500]);

    hPie = pie(times);

    % 设置颜色
    patchHandles = findobj(hPie, 'Type', 'patch');
    for i = 1:numel(patchHandles)
        patchHandles(i).FaceColor = colors(i, :);
    end

    % 设置文字标签
    textHandles = findobj(hPie, 'Type', 'text');
    for i = 1:2:numel(textHandles)
        if i/2 <= numel(labels)
            pct = times(ceil(i/2)) / sum(times) * 100;
            textHandles(i).String = sprintf('%s\n%.1f ms (%.1f%%)', ...
                labels{ceil(i/2)}, times(ceil(i/2)), pct);
            textHandles(i).FontSize = 11;
            textHandles(i).FontWeight = 'bold';
        end
    end

    % 标题
    expName = resultsTable.Experiment{idx};
    title(sprintf('%s —— %s', params.title, expName), ...
        'FontSize', 14, 'FontWeight', 'bold');

    % 保存
    if ~isempty(params.savePath)
        exportgraphics(figHandle, params.savePath, 'Resolution', 300);
        fprintf('Pie chart saved: %s\n', params.savePath);
    end
end
