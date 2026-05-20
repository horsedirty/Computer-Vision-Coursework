%% estimate_global_transform.m —— 全局变换估计 (RANSAC)
% 编码规范：参见项目根目录 AGENTS.md
% 角色二 & 三协作实现
%
% 功能：从匹配点对中使用 RANSAC 拟合全局变换矩阵（仿射或投影）。
% 这是模块一的最终输出——后续所有平滑和补偿都基于这个变换矩阵序列。
%
% INPUT:
%   matchedPrev - K×2，前一帧匹配点坐标
%   matchedCurr - K×2，当前帧匹配点坐标
%   params      - 参数字典
%     .transformType   - 'affine' | 'projective' | 'similarity' | 'rigid'
%                         默认 'affine'
%     .ransacMaxDist    - RANSAC 最大重投影误差（像素），默认 3
%     .ransacConfidence - RANSAC 置信度，默认 99.9
%     .ransacMaxTrials  - RANSAC 最大迭代次数，默认 2000
%     .compareModels    - 是否同时拟合多种模型并选最优，默认 false
%
% OUTPUT:
%   T           - 3×3 变换矩阵（仿射或投影，取决于 transformType）
%   inlierIdx   - K×1 logical，内点标记
%   diagnostics - struct，包含内点率、重投影误差、各模型残差对比等
%
% TODO:
%   [ ] 调用 estimateGeometricTransform2D 拟合仿射变换
%   [ ] 调用 estimateGeometricTransform2D 拟合投影变换（可选对比）
%   [ ] 实现 compareModels 功能：同时拟合 affine + projective，选残差更低的
%   [ ] 输出详细的诊断信息（内点率太低时发出警告）
%   [ ] 验证 T 矩阵的数值稳定性（条件数、行列式）
%
% 依赖: Computer Vision Toolbox

function [T, inlierIdx, diagnostics] = estimate_global_transform(matchedPrev, matchedCurr, params)
    arguments
        matchedPrev (:,2) double
        matchedCurr (:,2) double
        params struct = struct()
    end

    if ~isfield(params, 'transformType'),    params.transformType = 'affine'; end
    if ~isfield(params, 'ransacMaxDist'),     params.ransacMaxDist = 3; end
    if ~isfield(params, 'ransacConfidence'),  params.ransacConfidence = 99.9; end
    if ~isfield(params, 'ransacMaxTrials'),   params.ransacMaxTrials = 2000; end
    if ~isfield(params, 'compareModels'),     params.compareModels = false; end

    % === 主拟合 ===
    % TODO:
    % switch params.transformType
    %     case 'affine'
    %         tform = estimateGeometricTransform2D(matchedPrev, matchedCurr, 'affine', ...
    %             'MaxDistance', params.ransacMaxDist, ...
    %             'Confidence', params.ransacConfidence, ...
    %             'MaxNumTrials', params.ransacMaxTrials);
    %     case 'projective'
    %         tform = estimateGeometricTransform2D(matchedPrev, matchedCurr, 'projective', ...
    %             'MaxDistance', params.ransacMaxDist, ...
    %             'Confidence', params.ransacConfidence);
    %     case 'similarity'
    %         tform = estimateGeometricTransform2D(matchedPrev, matchedCurr, 'similarity', ...
    %             'MaxDistance', params.ransacMaxDist);
    %     case 'rigid'
    %         tform = estimateGeometricTransform2D(matchedPrev, matchedCurr, 'rigid', ...
    %             'MaxDistance', params.ransacMaxDist);
    %     otherwise
    %         error('不支持的变换类型: %s', params.transformType);
    % end
    % T = tform.T;
    % 注: MATLAB 输出的是 3×3 矩阵（仿射/投影统一形式）

    % === 可选：多模型对比 ===
    % if params.compareModels
    %     TODO: 同时拟合 affine + projective，对比内点率和重投影误差中位数
    %     选效果更好的模型，将对比数据填入 diagnostics
    % end

    % --- 占位 ---
    T = eye(3);
    inlierIdx = true(size(matchedPrev, 1), 1);
    diagnostics = struct('inlierRatio', 1.0, 'meanReprojError', 0, 'transformType', params.transformType);
end
