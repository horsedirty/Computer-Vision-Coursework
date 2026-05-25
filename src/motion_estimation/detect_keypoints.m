%% detect_keypoints.m —— 多检测器协作关键点检测
% 编码规范：参见项目根目录 AGENTS.md
% 角色二负责实现
%
% 功能：对输入帧执行 SIFT + SURF + ORB 多检测器协作，输出合并后的关键点集合。
% 参考论文：14_LightStab (CVPR 2026) 第 3.1 节多检测器协作机制
%
% 核心流程：
%   各检测器独立检测 → 取并集 + 按置信度排序 → NMS 合并重复点
%   → [弱纹理保底] 点 < 30 时追加 Harris 角点 → SSC 网格均匀化
%
% INPUT:
%   frame       - 输入帧图像，uint8 H×W×3（彩色）或 H×W（灰度）
%   params      - 参数字典 struct，字段包括：
%     .detectors         - 使用的检测器列表，默认 {'SIFT', 'SURF', 'ORB'}
%     .sift_nPoints      - SIFT 最强特征点数量，默认 500
%     .surf_nPoints      - SURF 最强特征点数量，默认 500
%     .orb_nPoints       - ORB 最强特征点数量，默认 500
%     .harris_nPoints    - Harris 保底追加数量，默认 30
%     .nms_radius        - 非极大值抑制半径（像素），默认 8
%     .grid_rows         - 网格均匀化行数，默认 6
%     .grid_cols         - 网格均匀化列数，默认 8
%     .top_k_per_grid    - 每网格保留 Top-K 点，默认 5
%     .min_dist          - 网格均匀化最小间距（像素），默认 5
%     .min_keypoints     - 弱纹理触发阈值，默认 30
%
% OUTPUT:
%   keypoints   - M×2 double，合并后的关键点坐标 [x, y]
%   scores      - M×1 double，对应置信度分数
%   detectorMap - M×1 cell，每点来源检测器名称 {'SIFT' | 'SURF' | 'ORB' | 'HARRIS'}
%   diagnostics - struct
%     .rawCounts   - struct，各检测器原始检测数
%     .nms_removed - NMS 剔除数
%     .harris_added- Harris 追加数（弱纹理时）
%     .finalCounts - 最终均匀化后各检测器来源数
%     .totalTime_ms- 总耗时
%
% 依赖: Computer Vision Toolbox

function [keypoints, scores, detectorMap, diagnostics] = detect_keypoints(frame, params)
    arguments
        frame (:,:) uint8
        params struct = struct()
    end

    t_start = tic;

    % === 参数初始化 ===
    if ~isfield(params, 'detectors'),      params.detectors = {'SIFT', 'SURF', 'ORB'}; end
    if ~isfield(params, 'sift_nPoints'),   params.sift_nPoints = 500; end
    if ~isfield(params, 'surf_nPoints'),   params.surf_nPoints = 500; end
    if ~isfield(params, 'orb_nPoints'),    params.orb_nPoints = 500; end
    if ~isfield(params, 'harris_nPoints'), params.harris_nPoints = 30; end
    if ~isfield(params, 'nms_radius'),     params.nms_radius = 8; end
    if ~isfield(params, 'grid_rows'),      params.grid_rows = 6; end
    if ~isfield(params, 'grid_cols'),      params.grid_cols = 8; end
    if ~isfield(params, 'top_k_per_grid'), params.top_k_per_grid = 5; end
    if ~isfield(params, 'min_dist'),       params.min_dist = 5; end
    if ~isfield(params, 'min_keypoints'),  params.min_keypoints = 30; end

    % === 灰度转换 ===
    if size(frame, 3) == 3
        grayFrame = rgb2gray(frame);
    else
        grayFrame = frame;
    end

    [H, W] = size(grayFrame);

    allKeypoints = [];
    allScores = [];
    allDetectors = {};
    rawCounts = struct();

    % === 各检测器独立检测 ===
    for d = 1:length(params.detectors)
        detName = upper(params.detectors{d});
        switch detName
            case 'SIFT'
                [pts, sc] = SIFT_detect(grayFrame, params.sift_nPoints);
            case 'SURF'
                [pts, sc] = SURF_detect(grayFrame, params.surf_nPoints);
            case 'ORB'
                [pts, sc] = ORB_detect(grayFrame, params.orb_nPoints);
            otherwise
                warning('不支持的检测器: %s，跳过', detName);
                continue;
        end
        nPts = size(pts, 1);
        rawCounts.(detName) = nPts;
        if nPts > 0
            allKeypoints = [allKeypoints; pts];
            allScores = [allScores; sc];
            allDetectors = [allDetectors; repmat({detName}, nPts, 1)];
        end
    end

    nBeforeNMS = size(allKeypoints, 1);

    % === 非极大值抑制 (NMS) 合并重复点 ===
    if nBeforeNMS > 0
        [allKeypoints, allScores, allDetectors] = ...
            nms_merge(allKeypoints, allScores, allDetectors, params.nms_radius);
    end
    nAfterNMS = size(allKeypoints, 1);
    nmsRemoved = nBeforeNMS - nAfterNMS;

    % === 弱纹理保底：点 < 30 时追加 Harris 角点 ===
    harrisAdded = 0;
    if nAfterNMS < params.min_keypoints
        harrisPts = HARRIS_detect(grayFrame, params.harris_nPoints);
        nHarris = size(harrisPts, 1);
        if nHarris > 0
            harrisScores = ones(nHarris, 1);
            harrisDetectors = repmat({'HARRIS'}, nHarris, 1);

            % 向量化欧氏距离去重：避免依赖 pdist2 (Statistics Toolbox)
            % dists2(i,j) = sum((harrisPts(i,:) - allPoints(j,:)).^2)
            harrisPtsD2 = sum(harrisPts.^2, 2);
            allPtsD2 = sum(allKeypoints.^2, 2)';
            crossTerm = harrisPts * allKeypoints';
            dists2 = harrisPtsD2 + allPtsD2 - 2 * crossTerm;

            minDists = sqrt(min(dists2, [], 2));
            keep = minDists > params.nms_radius;

            if any(keep)
                allKeypoints = [allKeypoints; harrisPts(keep, :)];
                allScores = [allScores; harrisScores(keep)];
                allDetectors = [allDetectors; harrisDetectors(keep)];
                harrisAdded = sum(keep);
            end
        end
    end

    nBeforeSSC = size(allKeypoints, 1);

    % === 网格均匀化 (Spatial Selective Clustering) ===
    if nBeforeSSC > 0
        [allKeypoints, allScores, allDetectors] = ...
            spatial_selective_clustering(allKeypoints, allScores, allDetectors, ...
                H, W, params.grid_rows, params.grid_cols, params.top_k_per_grid, params.min_dist);
    end

    % === 统计最终各检测器来源数 ===
    finalCounts = struct();
    for d = 1:length(params.detectors)
        detName = upper(params.detectors{d});
        finalCounts.(detName) = 0;
    end
    if harrisAdded > 0, finalCounts.HARRIS = 0; end
    for i = 1:length(allDetectors)
        detName = allDetectors{i};
        if isfield(finalCounts, detName)
            finalCounts.(detName) = finalCounts.(detName) + 1;
        else
            finalCounts.(detName) = 1;
        end
    end

    % === 输出 ===
    keypoints = allKeypoints;
    scores = allScores;
    detectorMap = allDetectors;
    elapsed = toc(t_start);
    diagnostics = struct(...
        'rawCounts', rawCounts, ...
        'nms_removed', nmsRemoved, ...
        'harris_added', harrisAdded, ...
        'finalCounts', finalCounts, ...
        'totalTime_ms', elapsed * 1000);
end


% =========================================================================
%% 子函数: 各检测器封装
% =========================================================================

function [pts, scores] = SIFT_detect(grayFrame, nPoints)
    points = detectSIFTFeatures(grayFrame);
    points = selectStrongest(points, nPoints);
    pts = points.Location;
    scores = points.Metric;
end

function [pts, scores] = SURF_detect(grayFrame, nPoints)
    points = detectSURFFeatures(grayFrame);
    points = selectStrongest(points, nPoints);
    pts = points.Location;
    scores = points.Metric;
end

function [pts, scores] = ORB_detect(grayFrame, nPoints)
    points = detectORBFeatures(grayFrame);
    points = selectStrongest(points, nPoints);
    pts = points.Location;
    scores = points.Metric;
end

function [pts, scores] = HARRIS_detect(grayFrame, nPoints)
    points = detectHarrisFeatures(grayFrame);
    points = selectStrongest(points, nPoints);
    pts = points.Location;
    scores = points.Metric;
end


% =========================================================================
%% 子函数: 非极大值抑制
% =========================================================================

function [filtered_pts, filtered_scores, filtered_detectors] = ...
    nms_merge(points, scores, detectors, radius)
    % 按置信度降序排序
    [scores, idx] = sort(scores, 'descend');
    points = points(idx, :);
    detectors = detectors(idx);

    N = size(points, 1);
    keep = true(N, 1);

    for i = 1:N
        if ~keep(i), continue; end
        % 只检查后面的点（前面的更高分已经处理过）
        for j = i+1:N
            if ~keep(j), continue; end
            dist = sqrt((points(i,1) - points(j,1))^2 + (points(i,2) - points(j,2))^2);
            if dist < radius
                keep(j) = false;
            end
        end
    end

    filtered_pts = points(keep, :);
    filtered_scores = scores(keep);
    filtered_detectors = detectors(keep);
end


% =========================================================================
%% 子函数: 网格均匀化 (Spatial Selective Clustering)
% =========================================================================

function [homogenized_pts, homogenized_scores, homogenized_detectors] = ...
    spatial_selective_clustering(points, scores, detectors, H, W, gridRows, gridCols, topK, minDist)
    % 将 [0,W]×[0,H] 划分为 gridRows×gridCols 网格
    % 每格取 topK 个最高分点，然后施加 minDist 最小间距约束

    if isempty(points)
        homogenized_pts = points;
        homogenized_scores = scores;
        homogenized_detectors = detectors;
        return;
    end

    candidates = [];
    candScores = [];
    candDetectors = {};

    % 按分数降序排列
    [scores, idx] = sort(scores, 'descend');
    points = points(idx, :);
    detectors = detectors(idx);

    xGrid = linspace(0, W, gridCols + 1);
    yGrid = linspace(0, H, gridRows + 1);

    for r = 1:gridRows
        for c = 1:gridCols
            xMin = xGrid(c); xMax = xGrid(c+1);
            yMin = yGrid(r); yMax = yGrid(r+1);

            inGrid = (points(:,1) >= xMin) & (points(:,1) < xMax) & ...
                     (points(:,2) >= yMin) & (points(:,2) < yMax);

            gridIdx = find(inGrid);
            if isempty(gridIdx), continue; end

            nTake = min(topK, length(gridIdx));
            for k = 1:nTake
                pi = gridIdx(k);
                candidates = [candidates; points(pi, :)];
                candScores = [candScores; scores(pi)];
                candDetectors = [candDetectors; detectors(pi)];
            end
        end
    end

    if isempty(candidates)
        homogenized_pts = zeros(0, 2);
        homogenized_scores = zeros(0, 1);
        homogenized_detectors = {};
        return;
    end

    % 最小间距约束：从高分到低分依次保留
    [candScores, idx] = sort(candScores, 'descend');
    candidates = candidates(idx, :);
    candDetectors = candDetectors(idx);

    M = size(candidates, 1);
    keep = true(M, 1);
    for i = 1:M
        if ~keep(i), continue; end
        for j = i+1:M
            if ~keep(j), continue; end
            dist = sqrt((candidates(i,1) - candidates(j,1))^2 + ...
                        (candidates(i,2) - candidates(j,2))^2);
            if dist < minDist
                keep(j) = false;
            end
        end
    end

    homogenized_pts = candidates(keep, :);
    homogenized_scores = candScores(keep);
    homogenized_detectors = candDetectors(keep);
end
