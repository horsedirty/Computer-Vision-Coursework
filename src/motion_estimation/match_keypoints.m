%% match_keypoints.m —— 关键点匹配
% 编码规范：参见项目根目录 AGENTS.md
% 角色二负责实现
%
% 功能：在连续两帧的关键点集合之间做特征描述子提取与匹配
%
% INPUT:
%   prevFrame   - 前一帧，uint8 H×W×3 或 H×W
%   currFrame   - 当前帧，uint8 H×W×3 或 H×W
%   prevKP      - 前一帧关键点坐标 M×2
%   currKP      - 当前帧关键点坐标 N×2
%   params      - 参数字典
%     .descriptor     - 描述子类型，'SIFT' | 'SURF' | 'FREAK'，默认 'SIFT'
%     .matchMethod    - 匹配方法，'Exhaustive' | 'Approximate'，默认 'Exhaustive'
%     .maxRatio       - Lowe's ratio test 阈值，默认 0.6
%     .unique         - 是否保留唯一匹配，默认 true
%
% OUTPUT:
%   matchedPrev - K×2 double，匹配上的前一帧点坐标
%   matchedCurr - K×2 double，匹配上的当前帧点坐标
%   matchScores - K×1 double，匹配距离（越小越好）
%   stats       - struct，匹配统计（匹配数、内点率预测等）
%
% TODO:
%   [ ] 对两帧分别提取特征描述子 (extractFeatures)
%   [ ] 执行暴力匹配 (matchFeatures)
%   [ ] 实现 Lowe's ratio test 筛选
%   [ ] 输出唯一匹配（去重）
%   [ ] 记录匹配统计信息

function [matchedPrev, matchedCurr, matchScores, stats] = match_keypoints(prevFrame, currFrame, prevKP, currKP, params)
    arguments
        prevFrame (:,:) uint8
        currFrame (:,:) uint8
        prevKP (:,2) double
        currKP (:,2) double
        params struct = struct()
    end

    if ~isfield(params, 'descriptor'),  params.descriptor = 'SIFT'; end
    if ~isfield(params, 'maxRatio'),    params.maxRatio = 0.6; end
    if ~isfield(params, 'unique'),      params.unique = true; end
    if ~isfield(params, 'matchMethod'), params.matchMethod = 'Exhaustive'; end

    % 灰度化
    if size(prevFrame, 3) == 3
        prevGray = rgb2gray(prevFrame);
        currGray = rgb2gray(currFrame);
    else
        prevGray = prevFrame;
        currGray = currFrame;
    end

    % === 关键点对象转换 ===
    % MATLAB 的 extractFeatures 需要 keypoint 对象而非裸坐标
    % TODO: 将 prevKP/currKP 转为 cornerPoints 或 SURFPoints 对象
    % prevPts = cornerPoints(prevKP);
    % currPts = cornerPoints(currKP);

    % === 提取描述子 ===
    % TODO: [prevFeatures, prevValidPts] = extractFeatures(prevGray, prevPts, 'Method', params.descriptor);
    % TODO: [currFeatures, currValidPts] = extractFeatures(currGray, currPts, 'Method', params.descriptor);

    % === 特征匹配 ===
    % TODO: indexPairs = matchFeatures(prevFeatures, currFeatures, ...
    %     'Method', params.matchMethod, 'MatchThreshold', 10, 'Unique', params.unique);

    % === Lowe's ratio test ===
    % TODO: 对每对匹配，计算最近邻距离 / 次近邻距离，若比值 > maxRatio 则剔除

    % === 输出 ===
    % matchedPrev = prevValidPts.Location(indexPairs(:,1), :);
    % matchedCurr = currValidPts.Location(indexPairs(:,2), :);

    matchedPrev = zeros(0, 2);
    matchedCurr = zeros(0, 2);
    matchScores = zeros(0, 1);
    stats = struct('numMatches', 0, 'meanDistance', 0, 'ratioTestRejected', 0);
end
