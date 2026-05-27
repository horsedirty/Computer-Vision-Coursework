%% run_motion_estimation.m —— 模块一主入口
% 编码规范：参见项目根目录 AGENTS.md
% 角色二 & 三共享接口
%
% 功能：串联关键点检测 → 匹配 → 光流计算 → 融合 → 全局变换估计的完整流程。
% 输入连续两帧，输出帧间全局变换矩阵。这是三阶段流水线的第一个模块。
%
% INPUT:
%   prevFrame   - 前一帧，uint8 H×W×3 彩色图
%   currFrame   - 当前帧，uint8 H×W×3 彩色图
%   params      - 参数字典，所有子模块参数统一在此传递
%     .detect_params   - 传递给 detect_keypoints 的参数
%     .match_params    - 传递给 match_keypoints 的参数
%     .flow_params     - 传递给 compute_optical_flow 的参数
%     .fuse_params     - 传递给 fuse_motion_field 的参数
%     .transform_params - 传递给 estimate_global_transform 的参数
%     .use_sparse_fusion - 是否启用稀疏光流融合，默认 true
%
% OUTPUT:
%   T           - 3×3 变换矩阵（当前帧相对于前一帧的全局运动）
%   diagnostics - struct，包含各子步骤耗时、内点率、匹配数等
%     .keypoint_count     - 检测到的关键点数量
%     .match_count        - 匹配上的点对数量
%     .inlier_ratio       - RANSAC 内点率
%     .flow_time_ms       - 光流计算耗时
%     .total_time_ms      - 模块总耗时
%
% 参考论文：14_LightStab (CVPR2026), 10_光流防抖 (CVPR2020), 11_多网格warping (TIP2019)

function [T, diagnostics] = run_motion_estimation(prevFrame, currFrame, params)
    arguments
        prevFrame uint8
        currFrame uint8
        params struct = struct()
    end

    % 手动维度验证（支持灰度和彩色帧）
    assert(ismatrix(prevFrame) || ndims(prevFrame) == 3, ...
        'prevFrame 必须是 2D（灰度）或 3D（彩色）uint8 矩阵');
    assert(ismatrix(currFrame) || ndims(currFrame) == 3, ...
        'currFrame 必须是 2D（灰度）或 3D（彩色）uint8 矩阵');

    t_total = tic;
    H = size(currFrame, 1);
    W = size(currFrame, 2);

    % --- 参数解包 ---
    detect_params    = safeField(params, 'detect_params', struct());
    match_params     = safeField(params, 'match_params', struct());
    flow_params      = safeField(params, 'flow_params', struct());
    fuse_params      = safeField(params, 'fuse_params', struct());
    transform_params = safeField(params, 'transform_params', struct());
    use_sparse_fusion = safeField(params, 'use_sparse_fusion', true);

    % 灰度转换：detect_keypoints 和 match_keypoints 要求2D灰度图
    if size(prevFrame, 3) == 3
        prevGray = rgb2gray(prevFrame);
        currGray = rgb2gray(currFrame);
    else
        prevGray = prevFrame;
        currGray = currFrame;
    end

    % ================================================================
    % 步骤 1: 关键点检测（角色二）
    % ================================================================
    t1 = tic;
    [prevKP, prevScores, prevDetMap, detectDiag1] = detect_keypoints(prevGray, detect_params);
    [currKP, currScores, ~, detectDiag2] = detect_keypoints(currGray, detect_params);
    detect_time = toc(t1);

    % ================================================================
    % 步骤 2: 关键点匹配（角色二）
    % ================================================================
    t2 = tic;
    [matchedPrev, matchedCurr, ~, matchDiag] = match_keypoints(prevGray, currGray, prevKP, currKP, match_params);
    match_time = toc(t2);

    % ================================================================
    % 步骤 3: 稠密光流（角色三）
    % ================================================================
    t3 = tic;
    [flow, flowDiag] = compute_optical_flow(prevGray, currGray, flow_params);
    flow_time = toc(t3);

    % ================================================================
    % 步骤 4: 稀疏光流融合（角色三）
    % 参考论文 14_LightStab (CVPR 2026) 第 3.1 节
    % ================================================================
    t4 = tic;
    if use_sparse_fusion && ~isempty(matchedPrev) && ~isempty(flow)
        [fusedFlow, ~, fuseDiag] = fuse_motion_field(flow, matchedPrev, matchedCurr, [H, W], fuse_params);
        if ~isempty(fusedFlow) && isfield(fusedFlow, 'Vx') && nnz(fusedFlow.Vx) > 0
            transform_params.fusedFlowVx = fusedFlow.Vx;
            transform_params.fusedFlowVy = fusedFlow.Vy;
        end
    else
        fuseDiag = struct('status', 'skipped');
    end
    fuse_time = toc(t4);

    % ================================================================
    % 步骤 5: 全局变换估计 RANSAC（角色二 & 三协作）
    % ================================================================
    t5 = tic;
    if size(matchedPrev, 1) >= 4  % 仿射变换至少需要 3 对点，投影需要 4 对
        [T, inlierIdx, transformDiag] = estimate_global_transform(matchedPrev, matchedCurr, transform_params);
    else
        warning('匹配点对数量不足 (%d < 4)，返回单位矩阵', size(matchedPrev, 1));
        T = eye(3);
        inlierIdx = [];
        transformDiag = struct('inlierRatio', NaN, 'meanReprojError', NaN);
    end
    transform_time = toc(t5);

    % ================================================================
    % 步骤 6a: 场景分类（角色二）
    % ================================================================
    nKeypoints = size(prevKP, 1);
    sceneType = classify_scene(flow, nKeypoints, struct());

    % ================================================================
    % 步骤 6b: 各检测器内点率统计（角色二）
    % ================================================================
    perDetectorStats = struct();
    if ~isempty(matchedPrev) && ~isempty(inlierIdx) && ~isempty(prevDetMap)
        [~, idxInPrev] = ismember(matchedPrev, prevKP, 'rows');
        validMatch = idxInPrev > 0;
        idxInPrev = idxInPrev(validMatch);
        inlierIdx = inlierIdx(validMatch);
        matchedDetectors = prevDetMap(idxInPrev);
        uniqueDets = unique(matchedDetectors);
        for d = 1:length(uniqueDets)
            detName = uniqueDets{d};
            detMask = strcmp(matchedDetectors, detName);
            nTotal = sum(detMask);
            nInlier = sum(inlierIdx(detMask));
            perDetectorStats.(detName) = struct(...
                'total', nTotal, 'inlier', nInlier, ...
                'inlierRate', nInlier / max(nTotal, 1));
        end
    end

    % ================================================================
    % 汇总诊断信息
    % ================================================================
    total_time = toc(t_total);

    diagnostics = struct(...
        'detect_time_ms',     detect_time * 1000, ...
        'match_time_ms',      match_time * 1000, ...
        'flow_time_ms',       flow_time * 1000, ...
        'fuse_time_ms',       fuse_time * 1000, ...
        'transform_time_ms',  transform_time * 1000, ...
        'total_time_ms',      total_time * 1000, ...
        'keypoint_count',     [size(prevKP,1), size(currKP,1)], ...
        'match_count',        size(matchedPrev, 1), ...
        'inlier_ratio',       transformDiag.inlierRatio, ...
        'scene_type',         sceneType, ...
        'per_detector_stats', perDetectorStats, ...
        'detect_details',     {detectDiag1, detectDiag2}, ...
        'match_details',      matchDiag, ...
        'flow_details',       flowDiag, ...
        'fuse_details',       fuseDiag, ...
        'transform_details',  transformDiag);
end


%% 辅助函数：安全获取 struct 字段，不存在则返回默认值
function val = safeField(s, fieldname, default)
    if isfield(s, fieldname)
        val = s.(fieldname);
    else
        val = default;
    end
end

