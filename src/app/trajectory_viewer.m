%% trajectory_viewer.m —— 轨迹可视化子窗口
% 编码规范：参见项目根目录 AGENTS.md
% 角色七负责实现
%
% 功能：在独立的 uifigure 中展示原始 vs 平滑后运动轨迹对比。
% 调用已实现的 visualize_trajectory，封装为 App Designer 可触发的弹出窗口。
% 参考论文 17_中北大学 (MDPI 2025) 的轨迹对比范式。
%
% INPUT:
%   T_raw_seq       - 3×3×N，原始变换矩阵序列
%   T_smoothed_seq  - 3×3×N，平滑后变换矩阵序列
%   params          - 参数字典
%     .title          - 窗口标题
%     .parent         - 父级 uifigure（用于居中定位）
%
% OUTPUT:
%   viewerFig   - uifigure 句柄
%   trajFig     - 内嵌坐标区句柄
%
% 依赖：
%   src/evaluation/visualize_trajectory.m（已有函数）

function [viewerFig, trajFig] = trajectory_viewer(T_raw_seq, T_smoothed_seq, params)
    arguments
        T_raw_seq (:,:,:) double
        T_smoothed_seq (:,:,:) double
        params struct = struct()
    end

    titleStr = safeField(params, 'title', '累积运动轨迹对比');
    parentFig = safeField(params, 'parent', []);

    % 创建独立窗口
    viewerFig = uifigure('Name', titleStr, 'NumberTitle', 'off', ...
        'Position', [100, 100, 700, 550]);

    % 相对于父窗口居中
    if ~isempty(parentFig) && isvalid(parentFig)
        parentPos = parentFig.Position;
        viewerFig.Position(1) = parentPos(1) + parentPos(3)/2 - 350;
        viewerFig.Position(2) = parentPos(2) + parentPos(4)/2 - 275;
    end

    % 使用 uiaxes 嵌入 uifigure
    trajFig = uiaxes(viewerFig, 'Position', [60, 60, 580, 440]);

    % 调用已有函数计算并绘制轨迹
    [figHandle, trajRaw, trajSmoothed] = visualize_trajectory(...
        T_raw_seq, T_smoothed_seq, struct('title', titleStr));

    % 将 figure 内容复制到 uiaxes
    if isvalid(figHandle)
        axOld = findobj(figHandle, 'Type', 'axes');
        if ~isempty(axOld)
            children = axOld.Children;
            copyobj(children, trajFig);
            trajFig.XLabel.String = '累积水平位移（像素）';
            trajFig.YLabel.String = '累积垂直位移（像素）';
            trajFig.Title.String = titleStr;
            legend(trajFig, '原始轨迹（含抖动）', '平滑后轨迹', 'Location', 'best');
            axis(trajFig, 'equal');
            grid(trajFig, 'on');
        end
        close(figHandle);
    end

    % 添加信息面板
    rangeRaw = max(sqrt(trajRaw(:,1).^2 + trajRaw(:,2).^2));
    rangeSm  = max(sqrt(trajSmoothed(:,1).^2 + trajSmoothed(:,2).^2));
    reduction = (1 - rangeSm / max(rangeRaw, 1e-6)) * 100;

    infoText = sprintf(['原始运动范围: %.1f px | 平滑后运动范围: %.1f px | ' ...
        '抖动抑制: %.1f%%'], rangeRaw, rangeSm, reduction);
    uilabel(viewerFig, 'Text', infoText, ...
        'Position', [60, 20, 580, 30], ...
        'HorizontalAlignment', 'center', ...
        'FontSize', 11);
end


%% 辅助函数
function val = safeField(s, fieldname, default)
    if isfield(s, fieldname)
        val = s.(fieldname);
    else
        val = default;
    end
end
