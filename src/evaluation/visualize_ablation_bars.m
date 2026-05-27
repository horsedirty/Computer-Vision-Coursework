%% visualize_ablation_bars.m —— Ablation Experiment Results Bar Chart Visualization
% Coding standard: See project root AGENTS.md
% Role 8 is responsible for implementation
%
% Function: Extract PSNR/SSIM/SR metrics from ablation experiment results table,
% generate grouped bar chart to visually compare performance differences across ablation configurations.
%
% INPUT:
%   resultsTable   - table from run_ablation_study output
%                     Must contain columns: Experiment, PSNR_dB, SSIM, SR
%   params         - parameter struct
%     .savePath      - save path, default ''
%     .title         - chart title, default 'Ablation Study Performance Comparison'
%     .sortBy        - sort criterion ('PSNR'/'SSIM'/'SR'), default 'PSNR'
%     .barWidth      - bar width, default 0.6
%
% OUTPUT:
%   figHandle      - figure handle

function figHandle = visualize_ablation_bars(resultsTable, params)
    arguments
        resultsTable table
        params struct = struct()
    end

    if ~isfield(params, 'savePath'),  params.savePath = ''; end
    if ~isfield(params, 'title'),     params.title = 'Ablation Study Performance Comparison'; end
    if ~isfield(params, 'sortBy'),    params.sortBy = 'PSNR'; end
    if ~isfield(params, 'barWidth'),  params.barWidth = 0.6; end

    nExp = height(resultsTable);

    % 提取数据
    names = resultsTable.Experiment;
    psnr  = resultsTable.PSNR_dB;
    ssim  = resultsTable.SSIM;
    sr    = resultsTable.SR;

    % 按指定指标排序
    switch upper(params.sortBy)
        case 'PSNR'
            [~, ord] = sort(psnr, 'descend');
        case 'SSIM'
            [~, ord] = sort(ssim, 'descend');
        case 'SR'
            [~, ord] = sort(sr, 'descend');
        otherwise
            ord = 1:nExp;
    end

    names = names(ord);
    psnr  = psnr(ord);
    ssim  = ssim(ord);
    sr    = sr(ord);

    % 创建三子图柱状图
    figHandle = figure('Name', params.title, 'NumberTitle', 'off', ...
        'Position', [100, 100, 900, 500]);

    % 子图 1: PSNR
    subplot(1, 3, 1);
    h1 = bar(psnr, params.barWidth, 'FaceColor', [0.2 0.6 0.9]);
    set(gca, 'XTickLabel', names, 'XTickLabelRotation', 45);
    ylabel('PSNR (dB)');
    title('PSNR', 'FontWeight', 'bold', 'FontSize', 12);
    grid on; box on;
    % 在柱顶标注数值
    if ~all(isnan(psnr))
        for i = 1:nExp
            if ~isnan(psnr(i))
                text(i, psnr(i) + 0.1, sprintf('%.2f', psnr(i)), ...
                    'HorizontalAlignment', 'center', 'FontSize', 8);
            end
        end
    end

    % 子图 2: SSIM
    subplot(1, 3, 2);
    h2 = bar(ssim, params.barWidth, 'FaceColor', [0.9 0.4 0.2]);
    set(gca, 'XTickLabel', names, 'XTickLabelRotation', 45);
    ylabel('SSIM');
    title('SSIM', 'FontWeight', 'bold', 'FontSize', 12);
    grid on; box on;
    if ~all(isnan(ssim))
        for i = 1:nExp
            if ~isnan(ssim(i))
                text(i, ssim(i) + 0.01, sprintf('%.3f', ssim(i)), ...
                    'HorizontalAlignment', 'center', 'FontSize', 8);
            end
        end
    end

    % 子图 3: SR
    subplot(1, 3, 3);
    h3 = bar(sr, params.barWidth, 'FaceColor', [0.2 0.8 0.4]);
    set(gca, 'XTickLabel', names, 'XTickLabelRotation', 45);
    ylabel('Stabilization Ratio SR');
    title('Stabilization Ratio', 'FontWeight', 'bold', 'FontSize', 12);
    grid on; box on;
    if ~all(isnan(sr))
        for i = 1:nExp
            if ~isnan(sr(i))
                text(i, sr(i) + 0.01, sprintf('%.2f', sr(i)), ...
                    'HorizontalAlignment', 'center', 'FontSize', 8);
            end
        end
    end

    % 总标题
    sgtitle(params.title, 'FontSize', 14, 'FontWeight', 'bold');

    % 保存
    if ~isempty(params.savePath)
        exportgraphics(figHandle, params.savePath, 'Resolution', 300);
        fprintf('Bar chart saved: %s\n', params.savePath);
    end
end
