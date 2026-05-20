%% visualize_frame_comparison.m —— 帧间稳定性对比可视化
% 编码规范：参见项目根目录 AGENTS.md
% 角色八负责实现
%
% 功能：生成 2×K 的帧对比图，上排原始、下排处理后，
% 直观展示防抖效果。
%
% INPUT:
%   rawFrames       - cell array，原始帧序列
%   stabilizedFrames - cell array，稳定后帧序列
%   frameIndices    - K×1，要展示的帧号
%   params          - 参数字典
%     .savePath       - 保存路径
%     .title          - 图标题
%     .labelFontSize  - 标签字号，默认 10
%
% OUTPUT:
%   figHandle       - figure 句柄

function figHandle = visualize_frame_comparison(rawFrames, stabilizedFrames, frameIndices, params)
    arguments
        rawFrames
        stabilizedFrames
        frameIndices (:,1) double
        params struct = struct()
    end

    if ~isfield(params, 'savePath'),       params.savePath = ''; end
    if ~isfield(params, 'title'),          params.title = '帧间稳定性对比'; end
    if ~isfield(params, 'labelFontSize'),  params.labelFontSize = 10; end

    K = length(frameIndices);
    figHandle = figure('Name', params.title, 'NumberTitle', 'off', ...
        'Position', [100, 100, 250*K, 500]);

    t = tiledlayout(2, K, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(t, params.title, 'FontWeight', 'bold', 'FontSize', 14);

    for k = 1:K
        idx = frameIndices(k);

        % 上排：原始帧
        nexttile(k);
        if iscell(rawFrames)
            imshow(rawFrames{idx});
        else
            imshow(rawFrames(:,:,:,idx));
        end
        title(sprintf('原始 #%d', idx), 'FontSize', params.labelFontSize);

        % 下排：稳定后帧
        nexttile(k + K);
        if iscell(stabilizedFrames)
            imshow(stabilizedFrames{idx});
        else
            imshow(stabilizedFrames(:,:,:,idx));
        end
        title(sprintf('稳定后 #%d', idx), 'FontSize', params.labelFontSize);
    end

    if ~isempty(params.savePath)
        exportgraphics(figHandle, params.savePath, 'Resolution', 300);
        fprintf('帧对比图已保存: %s\n', params.savePath);
    end
end
