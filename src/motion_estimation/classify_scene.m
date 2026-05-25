%% classify_scene.m —— 场景类型分类
% 编码规范：参见项目根目录 AGENTS.md
% 角色二负责实现
%
% 功能：基于光流和关键点密度，自动判断当前帧的场景类型。
% 用于后续按场景聚合各检测器的内点率，为自适应检测器切换提供依据。
%
% 场景类型（四类，按判定优先级排列）：
%   1. low_texture  — 弱纹理：关键点数量 < minKeypoints
%   2. large_motion — 大运动：光流幅度均值 > flowMeanLarge
%   3. dynamic_foreground — 动态前景：光流局部剧烈且分布不均匀
%   4. static       — 静态背景：以上条件均不满足
%
% INPUT:
%   flow        - opticalFlow 对象，包含 Vx, Vy, Magnitude
%   nKeypoints  - 当前帧检测到的关键点总数
%   params      - 参数字典
%     .minKeypoints    - 弱纹理判定阈值，默认 30
%     .flowMeanLarge   - 大运动光流均值阈值，默认 3.0
%     .flowMeanStatic  - 静态/动态区分阈值，默认 0.5
%     .flowStdRatio    - 局部/全局光流比阈值，默认 2.0
%
% OUTPUT:
%   sceneType   - char，'static' | 'dynamic_foreground' | 'low_texture' | 'large_motion'
%   diagnostics - struct
%     .flowMean         - 全局光流幅度均值
%     .flowStd          - 全局光流幅度标准差
%     .blockMeanMaxRatio - 局部块最大均值 / 全局均值
%     .nKeypoints       - 输入的关键点数量
%
% 依赖: Computer Vision Toolbox (opticalFlow)

function [sceneType, diagnostics] = classify_scene(flow, nKeypoints, params)
    arguments
        flow
        nKeypoints (1,1) double
        params struct = struct()
    end

    if ~isfield(params, 'minKeypoints'),   params.minKeypoints = 30; end
    if ~isfield(params, 'flowMeanLarge'),  params.flowMeanLarge = 3.0; end
    if ~isfield(params, 'flowMeanStatic'), params.flowMeanStatic = 0.5; end
    if ~isfield(params, 'flowStdRatio'),   params.flowStdRatio = 2.0; end

    % === 判断优先级 1: 弱纹理 ===
    if nKeypoints < params.minKeypoints
        sceneType = 'low_texture';
        diagnostics = struct(...
            'flowMean', NaN, 'flowStd', NaN, ...
            'blockMeanMaxRatio', NaN, 'nKeypoints', nKeypoints);
        return;
    end

    % === 从 flow 对象中提取幅度 ===
    if isempty(flow) || ~isvalid(flow)
        % 光流为空时默认返回静态
        sceneType = 'static';
        diagnostics = struct(...
            'flowMean', 0, 'flowStd', 0, ...
            'blockMeanMaxRatio', 1, 'nKeypoints', nKeypoints);
        return;
    end

    mag = flow.Magnitude;
    flowMean = mean(mag, 'all');
    flowStd  = std(mag, 0, 'all');

    % === 判断优先级 2: 大运动 ===
    if flowMean > params.flowMeanLarge
        sceneType = 'large_motion';
        diagnostics = struct(...
            'flowMean', flowMean, 'flowStd', flowStd, ...
            'blockMeanMaxRatio', NaN, 'nKeypoints', nKeypoints);
        return;
    end

    % === 判断优先级 3: 动态前景 ===
    % 将画面划分为 4×4 块，计算每块平均光流
    % 如果最大块均值 / 全局均值 > threshold，说明局部运动剧烈
    [H, W] = size(mag);
    nRows = 4; nCols = 4;
    rowStep = floor(H / nRows);
    colStep = floor(W / nCols);
    blockMeans = zeros(nRows, nCols);

    for r = 1:nRows
        for c = 1:nCols
            rRange = (r-1)*rowStep + 1 : min(r*rowStep, H);
            cRange = (c-1)*colStep + 1 : min(c*colStep, W);
            blockMeans(r, c) = mean(mag(rRange, cRange), 'all');
        end
    end

    blockMeanMaxRatio = max(blockMeans, [], 'all') / max(flowMean, 1e-6);

    if flowMean > params.flowMeanStatic && blockMeanMaxRatio > params.flowStdRatio
        sceneType = 'dynamic_foreground';
    else
        sceneType = 'static';
    end

    diagnostics = struct(...
        'flowMean', flowMean, 'flowStd', flowStd, ...
        'blockMeanMaxRatio', blockMeanMaxRatio, ...
        'nKeypoints', nKeypoints);
end
