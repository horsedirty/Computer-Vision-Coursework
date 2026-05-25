%% estimate_global_transform.m —— 全局变换估计 (RANSAC)
% 编码规范：参见项目根目录 AGENTS.md
% 角色二 & 三协作实现
%
% 功能：从匹配点对中使用 RANSAC 拟合全局变换矩阵（仿射或投影）。
% 这是模块一的最终输出——后续所有平滑和补偿都基于这个变换矩阵序列。
%
% 角色三扩展（从融合运动场拟合）：
%   - 可选接收稠密光流场 Vx, Vy，采样网格点对作为 RANSAC 的附加输入
%   - 稠密流提供全图均匀覆盖，比稀疏关键点更鲁棒
%   - 参考论文 14_LightStab (CVPR 2026) 第 3.1 节
%
% INPUT:
%   matchedPrev - K×2，前一帧匹配点坐标 [x, y]
%   matchedCurr - K×2，当前帧匹配点坐标 [x, y]
%   params      - 参数字典
%     .transformType    - 'affine' | 'projective' | 'similarity' | 'rigid'
%                         默认 'affine'
%     .ransacMaxDist     - RANSAC 最大重投影误差（像素），默认 3
%     .ransacConfidence  - RANSAC 置信度，默认 99.9
%     .ransacMaxTrials   - RANSAC 最大迭代次数，默认 2000
%     .compareModels     - 是否同时拟合多种模型并选最优，默认 false
%     .fusedFlowVx       - 融合运动场 Vx (H×W)，可选（角色三提供）
%     .fusedFlowVy       - 融合运动场 Vy (H×W)，可选（角色三提供）
%     .flowSampleStep    - 稠密流采样步长（像素），默认 10
%     .flowMaxSamples    - 稠密流最大采样点数，默认 2000
%
% OUTPUT:
%   T           - 3×3 变换矩阵（仿射或投影，取决于 transformType）
%   inlierIdx   - K×1 logical，内点标记（仅针对关键点，不含流动点）
%   diagnostics - struct，包含内点率、重投影误差、各模型残差对比等
%
% 依赖: Computer Vision Toolbox
%
% 参考论文：
%   - 14_LightStab (CVPR 2026): 从融合运动场拟合全局变换
%   - 09_GlobalFlowNet (WACV 2023): 全局运动估计与蒸馏
%   - 11_TIP2019: RANSAC 在多网格变换中的应用

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
    if ~isfield(params, 'fusedFlowVx'),       params.fusedFlowVx = []; end
    if ~isfield(params, 'fusedFlowVy'),       params.fusedFlowVy = []; end
    if ~isfield(params, 'flowSampleStep'),    params.flowSampleStep = 10; end
    if ~isfield(params, 'flowMaxSamples'),    params.flowMaxSamples = 2000; end

    t_start = tic;

    % === 从稠密运动场采样附加点对（角色三扩展） ===
    % 参考论文 14_LightStab 第 3.1 节：从融合运动场采样网格点，提供全图均匀覆盖
    flowSamplesUsed = 0;
    if ~isempty(params.fusedFlowVx) && ~isempty(params.fusedFlowVy)
        [Hf, Wf] = size(params.fusedFlowVx);
        step = max(1, params.flowSampleStep);

        % 均匀网格采样
        xGrid = 1:step:Wf;
        yGrid = 1:step:Hf;
        [Xg, Yg] = meshgrid(xGrid, yGrid);
        Xg = Xg(:);
        Yg = Yg(:);

        % 过滤 NaN 和异常大位移的点
        rIdx = min(max(round(Yg), 1), Hf);
        cIdx = min(max(round(Xg), 1), Wf);
        linearIdx = sub2ind([Hf, Wf], rIdx, cIdx);
        Vx_sampled = params.fusedFlowVx(linearIdx);
        Vy_sampled = params.fusedFlowVy(linearIdx);

        validFlow = ~isnan(Vx_sampled) & ~isnan(Vy_sampled) & ...
            abs(Vx_sampled) <= max(Wf, Hf) * 0.3 & abs(Vy_sampled) <= max(Wf, Hf) * 0.3;

        Vx_sampled = double(Vx_sampled);
        Vy_sampled = double(Vy_sampled);

        flowPrev = [Xg(validFlow), Yg(validFlow)];
        flowCurr = [Xg(validFlow) + Vx_sampled(validFlow), Yg(validFlow) + Vy_sampled(validFlow)];

        % 限制最大点数防止 RANSAC 过慢
        if size(flowPrev, 1) > params.flowMaxSamples
            idx = randperm(size(flowPrev, 1), params.flowMaxSamples);
            flowPrev = flowPrev(idx, :);
            flowCurr = flowCurr(idx, :);
        end
        flowSamplesUsed = size(flowPrev, 1);

        % 融合关键点与流采样点
        allPrev = [matchedPrev; flowPrev];
        allCurr = [matchedCurr; flowCurr];
    else
        allPrev = matchedPrev;
        allCurr = matchedCurr;
    end

    % === 主拟合 ===
    minPoints = 3;  % 仿射至少需要 3 对非共线点
    if strcmp(params.transformType, 'projective')
        minPoints = 4;
    end

    if size(allPrev, 1) < minPoints
        warning('有效点对数量不足 (%d < %d)，返回单位矩阵', size(allPrev, 1), minPoints);
        T = eye(3);
        inlierIdx = false(size(matchedPrev, 1), 1);
        diagnostics = struct(...
            'inlierRatio', NaN, 'meanReprojError', NaN, 'transformType', params.transformType, ...
            'flowSamplesUsed', flowSamplesUsed);
        return;
    end

    % --- 单模型拟合 ---
    if ~params.compareModels
        [T, inlierIdx, meanErr] = fitSingleModel(allPrev, allCurr, matchedPrev, matchedCurr, params);
        diagnostics = struct(...
            'inlierRatio', double(sum(inlierIdx)) / max(1, size(matchedPrev, 1)), ...
            'meanReprojError', meanErr, ...
            'transformType', params.transformType, ...
            'flowSamplesUsed', flowSamplesUsed, ...
            'totalSamples', size(allPrev, 1), ...
            'conditionNumber', cond(T(1:3,1:3)), ...
            'determinant', det(T(1:3,1:3)));
    else
        % --- 多模型对比 ---
        % 同时拟合 affine + projective，选残差更低的
        modelTypes = {'affine', 'projective'};
        bestErr = inf;
        bestT = eye(3);
        bestInliers = false(size(matchedPrev, 1), 1);
        bestType = '';
        compareResults = struct();

        for m = 1:numel(modelTypes)
            p = params;
            p.transformType = modelTypes{m};
            [T_cand, inliers_cand, err_cand] = fitSingleModel(allPrev, allCurr, ...
                matchedPrev, matchedCurr, p);
            compareResults.(modelTypes{m}) = struct(...
                'inlierRatio', double(sum(inliers_cand)) / max(1, size(matchedPrev, 1)), ...
                'meanReprojError', err_cand);
            if err_cand < bestErr
                bestErr = err_cand;
                bestT = T_cand;
                bestInliers = inliers_cand;
                bestType = modelTypes{m};
            end
        end

        T = bestT;
        inlierIdx = bestInliers;
        diagnostics = struct(...
            'inlierRatio', double(sum(inlierIdx)) / max(1, size(matchedPrev, 1)), ...
            'meanReprojError', bestErr, ...
            'transformType', bestType, ...
            'compareResults', compareResults, ...
            'flowSamplesUsed', flowSamplesUsed, ...
            'totalSamples', size(allPrev, 1), ...
            'conditionNumber', cond(bestT(1:3,1:3)), ...
            'determinant', det(bestT(1:3,1:3)));
    end

    % === 数值稳定性验证 ===
    % 条件数过大或行列式接近 0 的矩阵可能导致 warp 失败
    if cond(T(1:3,1:3)) > 1e6 || abs(det(T(1:3,1:3))) < 1e-10
        warning('变换矩阵数值不稳定 (cond=%.1e, det=%.1e)，可能需降为相似变换', ...
            cond(T(1:3,1:3)), det(T(1:3,1:3)));
    end

    % === 内点率过低警告 ===
    if isfield(diagnostics, 'inlierRatio') && ~isnan(diagnostics.inlierRatio) && diagnostics.inlierRatio < 0.3
        warning('RANSAC 内点率偏低 (%.1f%%), 运动估计可能不可靠', diagnostics.inlierRatio * 100);
    end

    elapsed = toc(t_start);
    diagnostics.elapsed_ms = elapsed * 1000;
end


%% 辅助函数：拟合单个模型
function [T, inlierIdx, meanErr] = fitSingleModel(allPrev, allCurr, matchedPrev, matchedCurr, params)
    try
        tform = estimateGeometricTransform2D(allPrev, allCurr, params.transformType, ...
            'MaxDistance', params.ransacMaxDist, ...
            'Confidence', params.ransacConfidence, ...
            'MaxNumTrials', min(params.ransacMaxTrials, 5000));

        T = tform.T;
        % T 是 (D+1)×(D+1) 矩阵（仿射: 3×3，投影: 3×3）
        if size(T, 1) < 3
            T(3, :) = [0, 0, 1];
        end

        % 针对原始关键点计算内点标记
        if size(matchedPrev, 1) > 0
            projPts = transformPointsForward(tform, matchedPrev);
            reprojErr = sqrt(sum((projPts - matchedCurr).^2, 2));
            inlierIdx = reprojErr <= params.ransacMaxDist * 1.5;  % 稍宽松的阈值
            meanErr = mean(reprojErr(inlierIdx));
            if isnan(meanErr)
                meanErr = inf;
            end
        else
            inlierIdx = true(0, 1);
            meanErr = 0;
        end
    catch ME
        warning('RANSAC 拟合失败 (%s)，返回单位矩阵', ME.message);
        T = eye(3);
        inlierIdx = false(size(matchedPrev, 1), 1);
        meanErr = inf;
    end
end


%% 自测（合成数据 + 稠密流采样）
%{
    fprintf('=== estimate_global_transform 自测 ===\n');

    rng(1);
    numPts = 50;
    % 生成随机点
    ptsPrev = rand(numPts, 2) * 100;
    % 应用已知仿射变换: 旋转 5° + 平移 (3, -2) + 缩放 1.02
    theta = 5 * pi / 180;
    A_true = [cos(theta), -sin(theta); sin(theta), cos(theta)] * 1.02;
    t_true = [3; -2];
    ptsCurr = (A_true * ptsPrev')' + repmat(t_true', numPts, 1);
    % 加入少量噪声
    ptsCurr = ptsCurr + randn(numPts, 2) * 0.5;
    % 加入几个外点
    ptsCurr(end-2:end, :) = ptsPrev(end-2:end, :) + randn(3, 2) * 20;

    params = struct('transformType', 'affine', 'ransacMaxDist', 2, ...
        'ransacConfidence', 99, 'ransacMaxTrials', 1000);

    [T, inliers, diag] = estimate_global_transform(ptsPrev, ptsCurr, params);
    fprintf('内点率: %.2f | 重投影误差: %.2f px | 类型: %s\n', ...
        diag.inlierRatio, diag.meanReprojError, diag.transformType);
    fprintf('条件数: %.1e | 行列式: %.4f | 耗时: %.1f ms\n', ...
        diag.conditionNumber, diag.determinant, diag.elapsed_ms);

    % 验证 T 接近已知真值
    T_affine = T(1:2, 1:2)  % 应接近 A_true
    T_trans  = T(1:2, 3)    % 应接近 t_true

    % 测试稠密流采样
    fprintf('\n--- 稠密流采样测试 ---\n');
    H = 200; W = 300;
    [Xg, Yg] = meshgrid(1:W, 1:H);
    Vx_true = Xg * (A_true(1,1)-1) + Yg * A_true(1,2) + t_true(1);
    Vy_true = Xg * A_true(2,1) + Yg * (A_true(2,2)-1) + t_true(2);
    params.fusedFlowVx = Vx_true + randn(H, W) * 0.3;
    params.fusedFlowVy = Vy_true + randn(H, W) * 0.3;
    params.flowSampleStep = 8;

    [T2, inliers2, diag2] = estimate_global_transform(ptsPrev, ptsCurr, params);
    fprintf('含流采样 - 内点率: %.2f | 流采样点数: %d | 总采样: %d\n', ...
        diag2.inlierRatio, diag2.flowSamplesUsed, diag2.totalSamples);

    % 测试 compareModels
    fprintf('\n--- 多模型对比 ---\n');
    params3 = struct('compareModels', true, 'ransacMaxDist', 2);
    [T3, ~, diag3] = estimate_global_transform(ptsPrev, ptsCurr, params3);
    fprintf('最优模型: %s | 内点率: %.2f\n', diag3.transformType, diag3.inlierRatio);
    if isfield(diag3, 'compareResults')
        fn = fieldnames(diag3.compareResults);
        for i = 1:numel(fn)
            r = diag3.compareResults.(fn{i});
            fprintf('  %s: 内点率 %.3f, 残差 %.3f\n', fn{i}, r.inlierRatio, r.meanReprojError);
        end
    end
%}
