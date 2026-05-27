%% match_keypoints.m —— Keypoint Matching
% Coding standard: See project root AGENTS.md
% Implemented by Role 2
%
% Function: Extract feature descriptors and match between keypoint sets of two consecutive frames
%
% INPUT:
%   prevFrame   - Previous frame, uint8 H×W×3 or H×W
%   currFrame   - Current frame, uint8 H×W×3 or H×W
%   prevKP      - Previous frame keypoint coordinates M×2
%   currKP      - Current frame keypoint coordinates N×2
%   params      - Parameter dictionary
%     .descriptor     - Descriptor type, 'SIFT' | 'SURF' | 'FREAK', default 'SIFT'
%     .matchMethod    - Matching method, 'Exhaustive' | 'Approximate', default 'Exhaustive'
%     .maxRatio       - Lowe's ratio test threshold, default 0.6
%     .unique         - Whether to retain unique matches, default true
%
% OUTPUT:
%   matchedPrev - K×2 double, matched previous frame point coordinates
%   matchedCurr - K×2 double, matched current frame point coordinates
%   matchScores - K×1 double, matching distance (smaller is better)
%   stats       - struct, matching statistics
%     .numMatches        - Number of successful matches
%     .meanDistance      - Average matching distance
%     .ratioTestRejected - Estimated number of matches rejected by Lowe's ratio test
%
% Dependency: Computer Vision Toolbox

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

    % === Empty frame protection ===
    if isempty(prevKP) || isempty(currKP)
        matchedPrev = zeros(0, 2);
        matchedCurr = zeros(0, 2);
        matchScores = zeros(0, 1);
        stats = struct('numMatches', 0, 'meanDistance', 0, 'ratioTestRejected', 0);
        return;
    end

    % === Grayscale conversion ===
    if size(prevFrame, 3) == 3
        prevGray = rgb2gray(prevFrame);
        currGray = rgb2gray(currFrame);
    else
        prevGray = prevFrame;
        currGray = currFrame;
    end

    % === Keypoint object conversion ===
    % SIFT descriptor requires SIFTPoints, other descriptors use cornerPoints
    if strcmpi(params.descriptor, 'SIFT')
        prevPts = SIFTPoints(prevKP);
        currPts = SIFTPoints(currKP);
    else
        prevPts = cornerPoints(prevKP);
        currPts = cornerPoints(currKP);
    end

    % === Extract descriptors ===
    [prevFeatures, prevValidPts] = extractFeatures(prevGray, prevPts, 'Method', params.descriptor);
    [currFeatures, currValidPts] = extractFeatures(currGray, currPts, 'Method', params.descriptor);

    % === Empty feature protection ===
    if isempty(prevFeatures) || isempty(currFeatures)
        matchedPrev = zeros(0, 2);
        matchedCurr = zeros(0, 2);
        matchScores = zeros(0, 1);
        stats = struct('numMatches', 0, 'meanDistance', 0, 'ratioTestRejected', 0);
        return;
    end

    nPrevFeat = size(prevFeatures, 1);
    nCurrFeat = size(currFeatures, 1);

    % === Feature matching (with Lowe's ratio test) ===
    % MaxRatio parameter in matchFeatures implements Lowe's ratio test
    indexPairs = matchFeatures(prevFeatures, currFeatures, ...
        'Method', params.matchMethod, ...
        'MatchThreshold', 10.0, ...
        'MaxRatio', params.maxRatio, ...
        'Unique', params.unique);

    % === Output ===
    if isempty(indexPairs)
        matchedPrev = zeros(0, 2);
        matchedCurr = zeros(0, 2);
        matchScores = zeros(0, 1);
        stats = struct('numMatches', 0, 'meanDistance', 0, 'ratioTestRejected', nPrevFeat + nCurrFeat);
        return;
    end

    matchedPrev = prevValidPts.Location(indexPairs(:,1), :);
    matchedCurr = currValidPts.Location(indexPairs(:,2), :);

    % Estimate match scores (inverse distance, smaller is better)
    matchScores = zeros(size(indexPairs, 1), 1);

    nMatches = size(matchedPrev, 1);
    ratioRejected = max(0, min(nPrevFeat, nCurrFeat) - nMatches);

    stats = struct(...
        'numMatches', nMatches, ...
        'meanDistance', mean(matchScores), ...
        'ratioTestRejected', ratioRejected);
end
