%% fuse_motion_field.m —— 稀疏关键点引导的光流融合
% 编码规范：参见项目根目录 AGENTS.md
% 角色三负责实现
%
% 功能：将稠密光流与稀疏关键点匹配融合，生成"干净的"运动场。
% 核心思路（参考论文 14_LightStab, CVPR 2026, 第 3.1 节）：
%   - 在关键点邻域（半径 r）内保留稠密光流的精度
%   - 在邻域外用关键点对应关系做散点插值
%   - 这样动态物体区域（关键点匹配通常失败的区域）不会污染运动场
%
% INPUT:
%   flow        - 稠密光流对象 (opticalFlow) 或包含 Vx, Vy 的 struct
%   matchedPrev - K×2，匹配上的前一帧点坐标 [x, y]
%   matchedCurr - K×2，匹配上的当前帧点坐标 [x, y]
%   frameSize   - [H, W]，帧尺寸
%   params      - 参数字典
%     .neighbor_radius - 关键点邻域半径（像素），默认 15
%     .interp_method   - 插值方法: 'linear' | 'natural' | 'nearest'，默认 'linear'
%     .blend_width      - 掩码边界混合过渡宽度（像素），默认 5
%     .coarse_step      - 插值粗网格步长（提速），默认 4
%
% OUTPUT:
%   fusedFlow   - struct，融合后的运动场，包含 Vx(H×W), Vy(H×W)
%   mask        - H×W logical，标记使用稠密光流的区域（= 在关键点邻域内）
%   diagnostics - struct
%
% 依赖: Image Processing Toolbox
%
% 参考论文：
%   - 14_LightStab (CVPR 2026): 稀疏关键点引导光流融合
%   - 10_CVPR2020: 光流用于稳定化的范式
%   - 11_TIP2019: 网格级计算参考

function [fusedFlow, mask, diagnostics] = fuse_motion_field(flow, matchedPrev, matchedCurr, frameSize, params)
    arguments
        flow
        matchedPrev (:,2) double
        matchedCurr (:,2) double
        frameSize (1,2) double
        params struct = struct()
    end

    if ~isfield(params, 'neighbor_radius'), params.neighbor_radius = 15; end
    if ~isfield(params, 'interp_method'),   params.interp_method = 'linear'; end
    if ~isfield(params, 'blend_width'),     params.blend_width = 5; end
    if ~isfield(params, 'coarse_step'),     params.coarse_step = 4; end

    H = frameSize(1);
    W = frameSize(2);
    t_start = tic;

    % === 从光流对象中提取 Vx, Vy ===
    if isa(flow, 'opticalFlow')
        Vx_flow = double(flow.Vx);
        Vy_flow = double(flow.Vy);
    elseif isstruct(flow) && isfield(flow, 'Vx') && isfield(flow, 'Vy')
        Vx_flow = double(flow.Vx);
        Vy_flow = double(flow.Vy);
    elseif isempty(flow)
        Vx_flow = zeros(H, W);
        Vy_flow = zeros(H, W);
    else
        error('flow 必须是 opticalFlow 对象或包含 Vx, Vy 的 struct');
    end

    % === 生成关键点邻域掩码 ===
    % 参考论文 14_LightStab 第 3.1 节：在关键点邻域保留稠密流
    % 先用稀疏标记图 + imdilate 高效生成邻域掩码
    if isempty(matchedPrev) || size(matchedPrev, 1) == 0
        mask = false(H, W);
    else
        % 向量化关键点标记（避免逐点 for 循环）
        kpX = round(matchedPrev(:, 1));
        kpY = round(matchedPrev(:, 2));
        inBounds = kpX >= 1 & kpX <= W & kpY >= 1 & kpY <= H;
        kpX = kpX(inBounds);
        kpY = kpY(inBounds);
        linearIdx = sub2ind([H, W], kpY, kpX);
        markers = false(H, W);
        markers(linearIdx) = true;
        se = strel('disk', double(params.neighbor_radius), 0);
        mask = imdilate(markers, se);
    end

    % === 掩码过渡带 ===
    % 对 mask 做边缘膨胀，生成过渡带用于平滑融合，避免硬切换伪影
    if params.blend_width > 0 && nnz(mask) > 0
        seBlend = strel('disk', double(params.blend_width), 0);
        maskOuter = imdilate(mask, seBlend);
        transitionZone = maskOuter & ~mask;
        % 过渡权重：从 mask 边界向外线性衰减
        distToMask = bwdist(mask);  % 到 mask 内部的距离
        if any(transitionZone(:))
            maxDist = max(distToMask(transitionZone(:)));
            if maxDist > 0
                blendWeight = min(1, (maxDist - distToMask) / maxDist);
            else
                blendWeight = double(mask);
            end
        else
            blendWeight = double(mask);
        end
    else
        blendWeight = double(mask);
    end

    % === 在掩码外部做散点插值 ===
    % 计算稀疏匹配点的位移向量，用 scatteredInterpolant 插值到全图
    % 参考论文 14_LightStab 第 3.1 节：关键点对应提供 clean 的运动先验
    if isempty(matchedPrev) || size(matchedPrev, 1) < 3
        Vx_interp = Vx_flow;
        Vy_interp = Vy_flow;
    else
        disp_x = matchedCurr(:, 1) - matchedPrev(:, 1);
        disp_y = matchedCurr(:, 2) - matchedPrev(:, 2);

        % 过滤异常值：位移超过帧尺寸 1/4 的点视为异常
        maxDisp = max(H, W) / 4;
        validDisp = abs(disp_x) <= maxDisp & abs(disp_y) <= maxDisp;
        if sum(validDisp) >= 3
            matchedPrev_f = matchedPrev(validDisp, :);
            disp_x_f = disp_x(validDisp);
            disp_y_f = disp_y(validDisp);
        else
            matchedPrev_f = matchedPrev;
            disp_x_f = disp_x;
            disp_y_f = disp_y;
        end

        % 在粗网格上插值，然后上采样到全分辨率（性能优化）
        coarseStep = max(1, params.coarse_step);
        XqCoarse = 1:coarseStep:W;
        YqCoarse = 1:coarseStep:H;
        [XqC, YqC] = meshgrid(XqCoarse, YqCoarse);
        Hc = length(YqCoarse);
        Wc = length(XqCoarse);

        % 去重：scatteredInterpolant 不允许重复坐标点，先对重复点求平均
        [~, ia, ~] = unique(matchedPrev_f, 'rows', 'stable');
        if length(ia) < size(matchedPrev_f, 1)
            % 存在重复点，用 accumarray 对位移值取平均
            [uniqPts, ~, ic] = unique(matchedPrev_f, 'rows', 'stable');
            nUniq = size(uniqPts, 1);
            avg_dx = accumarray(ic, disp_x_f, [nUniq, 1], @mean);
            avg_dy = accumarray(ic, disp_y_f, [nUniq, 1], @mean);
            matchedPrev_f = uniqPts;
            disp_x_f = avg_dx;
            disp_y_f = avg_dy;
        end

        try
            Fx = scatteredInterpolant(matchedPrev_f(:,1), matchedPrev_f(:,2), disp_x_f, ...
                params.interp_method, 'nearest');
            Fy = scatteredInterpolant(matchedPrev_f(:,1), matchedPrev_f(:,2), disp_y_f, ...
                params.interp_method, 'nearest');
            Vx_coarse = Fx(XqC, YqC);
            Vy_coarse = Fy(XqC, YqC);
            Vx_interp = imresize(Vx_coarse, [H, W], 'bilinear');
            Vy_interp = imresize(Vy_coarse, [H, W], 'bilinear');
        catch
            % 插值失败时回退到光流
            warning('稀疏插值失败，回退到纯光流');
            mask = true(H, W);
            blendWeight = ones(H, W);
            Vx_interp = Vx_flow;
            Vy_interp = Vy_flow;
        end
    end

    % === 融合 ===
    % mask 内：稠密光流  |  mask 外：稀疏插值  |  过渡带：加权混合
    Vx_fused = blendWeight .* Vx_flow + (1 - blendWeight) .* Vx_interp;
    Vy_fused = blendWeight .* Vy_flow + (1 - blendWeight) .* Vy_interp;

    % 填充 NaN（光流可能在边界处产生 NaN）
    Vx_fused(isnan(Vx_fused)) = 0;
    Vy_fused(isnan(Vy_fused)) = 0;

    elapsed = toc(t_start);

    fusedFlow = struct('Vx', single(Vx_fused), 'Vy', single(Vy_fused));
    diagnostics = struct(...
        'mask_coverage', nnz(mask) / (H * W), ...
        'num_keypoints', size(matchedPrev, 1), ...
        'neighbor_radius', params.neighbor_radius, ...
        'interp_method', params.interp_method, ...
        'elapsed_ms', elapsed * 1000);
end


%% 自测（合成数据验证融合逻辑）
%{
    fprintf('=== fuse_motion_field 自测 ===\n');

    H = 240; W = 320;

    % 合成光流：全局平移 (dx=3, dy=-2)
    [Xg, Yg] = meshgrid(1:W, 1:H);
    Vx_flow = single(3 * ones(H, W));
    Vy_flow = single(-2 * ones(H, W));
    mockFlow = struct('Vx', Vx_flow, 'Vy', Vy_flow);

    % 合成关键点：在图像中心区域随机散布
    rng(42);
    numKP = 30;
    kpX = W*0.2 + rand(numKP, 1) * W*0.6;
    kpY = H*0.2 + rand(numKP, 1) * H*0.6;
    matchedPrev = [kpX, kpY];
    matchedCurr  = [kpX + 3, kpY - 2];  % 一致的全局平移

    % 加入一个"动态物体"点（位移异常）
    matchedPrev(end+1, :) = [W*0.5, H*0.3];
    matchedCurr(end+1, :)  = [W*0.5 + 20, H*0.3 - 15];

    params = struct('neighbor_radius', 15, 'interp_method', 'linear', ...
        'blend_width', 5, 'coarse_step', 4);
    [fused, mask, diag] = fuse_motion_field(mockFlow, matchedPrev, matchedCurr, [H, W], params);

    fprintf('掩码覆盖率: %.3f | 关键点数: %d | 耗时: %.1f ms\n', ...
        diag.mask_coverage, diag.num_keypoints, diag.elapsed_ms);

    % 验证融合后的位移均值接近 (3, -2)
    fprintf('融合 Vx 均值: %.2f (期望: 3.0)\n', mean(fused.Vx, 'all'));
    fprintf('融合 Vy 均值: %.2f (期望: -2.0)\n', mean(fused.Vy, 'all'));

    % 验证 mask 区域保留稠密流
    maskVx = fused.Vx(mask);
    fprintf('Mask 内 Vx 均值: %.2f (期望接近 3.0)\n', mean(maskVx(:)));

    % 测试空关键点
    [~, maskEmpty, diagEmpty] = fuse_motion_field(mockFlow, zeros(0,2), zeros(0,2), [H, W], params);
    fprintf('空关键点 - 掩码覆盖率: %.3f (期望: 0)\n', diagEmpty.mask_coverage);
%}
