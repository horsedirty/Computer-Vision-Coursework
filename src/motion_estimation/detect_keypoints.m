%% detect_keypoints.m —— 多检测器协作关键点检测
% 编码规范：参见项目根目录 AGENTS.md
% 角色二负责实现
%
% 功能：对输入帧执行 SIFT + SURF 双检测器协作，输出合并后的关键点集合
% 参考论文：14_LightStab (CVPR 2026) 第 3.1 节多检测器协作机制
%
% INPUT:
%   frame       - 输入帧图像，uint8 H×W×3（彩色）或 H×W（灰度）
%   params      - 参数字典 struct，字段包括：
%     .detectors         - 使用的检测器列表，默认 {'SIFT', 'SURF'}
%     .sift_nPoints      - SIFT 最强特征点数量，默认 500
%     .surf_nPoints      - SURF 最强特征点数量，默认 500
%     .nms_radius        - 非极大值抑制半径（像素），默认 8
%     .grid_rows         - 网格均匀化行数，默认 6
%     .grid_cols         - 网格均匀化列数，默认 8
%     .top_k_per_grid    - 每网格保留 Top-K 点，默认 5
%
% OUTPUT:
%   keypoints   - M×2 double，合并后的关键点坐标 [x, y]
%   scores      - M×1 double，对应置信度分数
%   detectorMap - M×1 cell，每点来源检测器名称 {'SIFT' | 'SURF'}
%   diagnostics - struct，各检测器单独输出数量、合并后数量等统计信息
%
% TODO:
%   [ ] 实现 SIFT 检测器调用 (SIFT_detect)
%   [ ] 实现 SURF 检测器调用 (SURF_detect)
%   [ ] 实现坐标归一化（两个检测器的坐标域可能不同）
%   [ ] 实现加权融合：SIFT 和 SURF 对同一位置的检测给予更高置信度
%   [ ] 实现非极大值抑制 (NMS)
%   [ ] 实现网格均匀化 (Spatial Selective Clustering)
%   [ ] 实现弱纹理检测：若总点数 < params.min_keypoints，输出警告并切换到 Harris 角点保底
%
% 依赖的 MATLAB 工具函数：
%   detectSIFTFeatures, detectSURFfeatures, detectHarrisFeatures
%   selectStrongest, selectUniform

function [keypoints, scores, detectorMap, diagnostics] = detect_keypoints(frame, params)
    arguments
        frame (:,:) uint8
        params struct = struct()
    end

    % === 参数初始化 ===
    if ~isfield(params, 'detectors'),     params.detectors = {'SIFT', 'SURF'}; end
    if ~isfield(params, 'sift_nPoints'),  params.sift_nPoints = 500; end
    if ~isfield(params, 'surf_nPoints'),  params.surf_nPoints = 500; end
    if ~isfield(params, 'nms_radius'),    params.nms_radius = 8; end
    if ~isfield(params, 'grid_rows'),     params.grid_rows = 6; end
    if ~isfield(params, 'grid_cols'),     params.grid_cols = 8; end
    if ~isfield(params, 'top_k_per_grid'),params.top_k_per_grid = 5; end
    if ~isfield(params, 'min_keypoints'), params.min_keypoints = 30; end

    % === 灰度转换 ===
    if size(frame, 3) == 3
        grayFrame = rgb2gray(frame);
    else
        grayFrame = frame;
    end

    allKeypoints = [];
    allScores = [];
    allDetectors = {};

    % === SIFT 检测 ===
    % TODO: 调用 MATLAB detectSIFTFeatures，提取 points.Location 和 points.Metric
    % points_SIFT = detectSIFTFeatures(grayFrame);
    % points_SIFT = selectStrongest(points_SIFT, params.sift_nPoints);
    % allKeypoints = [allKeypoints; points_SIFT.Location];
    % allScores   = [allScores;   points_SIFT.Metric];
    % allDetectors = [allDetectors; repmat({'SIFT'}, points_SIFT.Count, 1)];

    % === SURF 检测 ===
    % TODO: 同上，调用 detectSURFfeatures
    % points_SURF = detectSURFFeatures(grayFrame);
    % points_SURF = selectStrongest(points_SURF, params.surf_nPoints);
    % ...

    % === 弱纹理回退：若总点数不足，追加 Harris 角点 ===
    % if size(allKeypoints, 1) < params.min_keypoints
    %     warning('检测点数量 %d < 阈值 %d，追加 Harris 角点', ...
    %         size(allKeypoints,1), params.min_keypoints);
    %     points_Harris = detectHarrisFeatures(grayFrame);
    %     points_Harris = selectStrongest(points_Harris, params.min_keypoints);
    %     ...
    % end

    % === 非极大值抑制 (NMS) ===
    % TODO: 按置信度降序排序，对每个点检查其 nms_radius 范围内是否有更高置信度点
    % 若有，则抑制当前点

    % === 网格均匀化 (Spatial Selective Clustering) ===
    % TODO: 将画面划分为 grid_rows × grid_cols 网格
    % 每格内取 top_k_per_grid 个最高置信度点
    % 相邻点施加最小间距约束

    % === 输出 ===
    % keypoints = ...;
    % scores = ...;
    % detectorMap = ...;
    % diagnostics = struct(...);

    % --- 占位：返回空（待实现后删除此行） ---
    keypoints = zeros(0, 2);
    scores = zeros(0, 1);
    detectorMap = {};
    diagnostics = struct('sift_count', 0, 'surf_count', 0, 'merged_count', 0);
end


% =========================================================================
%% 子函数: 单检测器封装
% =========================================================================

function [pts, scores] = SIFT_detect(grayFrame, nPoints)
    % TODO: 封装 detectSIFTFeatures 调用
    pts = [];
    scores = [];
end

function [pts, scores] = SURF_detect(grayFrame, nPoints)
    % TODO: 封装 detectSURFFeatures 调用
    pts = [];
    scores = [];
end


% =========================================================================
%% 子函数: 非极大值抑制
% =========================================================================

function [filtered_pts, filtered_scores] = NMS(points, scores, radius)
    % TODO: 实现基于距离的非极大值抑制
    % points: N×2, scores: N×1, radius: 抑制半径（像素）
    % 返回被保留的点
    filtered_pts = points;
    filtered_scores = scores;
end


% =========================================================================
%% 子函数: 网格均匀化
% =========================================================================

function [homogenized_pts, homogenized_scores] = spatial_selective_clustering(points, scores, H, W, gridRows, gridCols, topK)
    % TODO: 实现空间选择性聚类网格均匀化
    % 将 [0,H]×[0,W] 划分为 gridRows×gridCols 网格
    % 每格取 topK 个最高分点
    homogenized_pts = points;
    homogenized_scores = scores;
end
