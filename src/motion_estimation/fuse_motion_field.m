%% fuse_motion_field.m —— 稀疏关键点引导的光流融合
% 编码规范：参见项目根目录 AGENTS.md
% 角色三负责实现
%
% 功能：将稠密光流与稀疏关键点匹配融合，生成"干净的"运动场。
% 核心思路（参考论文 14_LightStab）：
%   - 在关键点邻域（半径 r）内保留稠密光流的精度
%   - 在邻域外用关键点对应关系做线性/径向基插值
%   - 这样动态物体区域（关键点匹配通常失败的区域）不会污染运动场
%
% INPUT:
%   flow        - 稠密光流对象 (opticalFlow)
%   matchedPrev - K×2，匹配上的前一帧点
%   matchedCurr - K×2，匹配上的当前帧点
%   frameSize   - [H, W]，帧尺寸
%   params      - 参数字典
%     .neighbor_radius - 关键点邻域半径（像素），默认 15
%     .interp_method   - 插值方法: 'linear' | 'rbf'，默认 'linear'
%
% OUTPUT:
%   fusedFlow   - struct，融合后的运动场，包含 Vx(H×W), Vy(H×W)
%   mask        - H×W logical，标记被稠密光流覆盖的区域（= 在关键点邻域内的像素）
%   diagnostics - struct
%
% TODO:
%   [ ] 从 flow 对象中提取 Vx, Vy 矩阵
%   [ ] 生成关键点邻域二值掩码 mask（imdilate + strel('disk', radius)）
%   [ ] 在 mask 外部区域，用 matchedPrev → matchedCurr 的位移做散点插值（griddata 或 scatteredInterpolant）
%   [ ] 在 mask 边界做混合过渡（避免硬切换造成的伪影）
%   [ ] 对比纯稠密光流 vs 融合光流在动态场景下的稳定性

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

    H = frameSize(1);
    W = frameSize(2);

    % === 从光流对象中提取 Vx, Vy ===
    % TODO: 检查 flow 类型并提取运动分量
    % Vx_flow = flow.Vx;
    % Vy_flow = flow.Vy;
    Vx_flow = zeros(H, W);
    Vy_flow = zeros(H, W);

    % === 生成关键点邻域掩码 ===
    % TODO: 创建一个全零的 H×W 逻辑矩阵
    % 对每个 matchedPrev 点，在 neighbor_radius 内标记为 true
    % 可用 imdilate + 二值标记图快速实现
    mask = false(H, W);

    % === 在掩码外部做散点插值 ===
    % TODO: 计算稀疏匹配点的位移向量
    % displacements = matchedCurr - matchedPrev;
    % 使用 scatteredInterpolant 在掩码外区域插值
    % 插值边界延伸到 mask 外围做平滑过渡

    % === 融合 ===
    % Vx_fused = mask .* Vx_flow + (~mask) .* Vx_interp;
    % Vy_fused = mask .* Vy_flow + (~mask) .* Vy_interp;

    fusedFlow = struct('Vx', Vx_flow, 'Vy', Vy_flow);
    diagnostics = struct('mask_coverage', nnz(mask) / (H*W));
end
