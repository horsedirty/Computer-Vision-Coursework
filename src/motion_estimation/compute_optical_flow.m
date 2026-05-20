%% compute_optical_flow.m —— 因果光流计算
% 编码规范：参见项目根目录 AGENTS.md
% 角色三负责实现
%
% 功能：在两帧之间计算稠密光流场。遵循因果约束——只用当前帧与前一帧，
% 不访问未来帧。输出稠密运动场供后续融合使用。
%
% INPUT:
%   prevFrame   - 前一帧，uint8 H×W 灰度图像
%   currFrame   - 当前帧，uint8 H×W 灰度图像
%   params      - 参数字典
%     .method     - 光流算法: 'Farneback' | 'HS' | 'LK' | 'LKDoG'
%                   默认 'Farneback'（稠密、效果好）
%     .pyramid    - Farneback 金字塔层数，默认 3
%     .scale      - 图像缩放因子（加速），默认 1.0
%
% OUTPUT:
%   flow        - opticalFlow 对象，包含 Vx, Vy, Magnitude, Orientation
%   diagnostics - struct，包含计算耗时、有效像素比例等
%
% TODO:
%   [ ] 实现 Farneback 光流 (opticalFlowFarneback) + 参数调优
%   [ ] 实现 Horn-Schunck 光流 (opticalFlowHS) 作为备选
%   [ ] 实现 Lucas-Kanade (opticalFlowLK) 作为稀疏备选
%   [ ] 各方法的速度/精度对比测试，输出推荐参数组合
%   [ ] 实现图像金字塔缩放以加速（先缩到一半算光流，再上采样）
%
% 依赖: Computer Vision Toolbox

function [flow, diagnostics] = compute_optical_flow(prevFrame, currFrame, params)
    arguments
        prevFrame (:,:) uint8
        currFrame (:,:) uint8
        params struct = struct()
    end

    if ~isfield(params, 'method'),  params.method = 'Farneback'; end
    if ~isfield(params, 'pyramid'), params.pyramid = 3; end
    if ~isfield(params, 'scale'),   params.scale = 1.0; end

    t_start = tic;

    % === 可选：缩放加速 ===
    % if params.scale < 1.0
    %     prevFrame = imresize(prevFrame, params.scale);
    %     currFrame = imresize(currFrame, params.scale);
    % end

    switch params.method
        case 'Farneback'
            % TODO: 创建 opticalFlowFarneback 对象并调用
            % opticFlow = opticalFlowFarneback('NumPyramidLevels', params.pyramid);
            % flow = estimateFlow(opticFlow, prevFrame);
            % flow = estimateFlow(opticFlow, currFrame);  % 第二次调用在 currFrame 上
            flow = [];

        case 'HS'
            % TODO: Horn-Schunck 实现
            % opticFlow = opticalFlowHS;
            % flow = estimateFlow(opticFlow, currGray);
            flow = [];

        case 'LK'
            % TODO: Lucas-Kanade 稀疏光流
            % opticFlow = opticalFlowLK;
            % flow = estimateFlow(opticFlow, currGray);
            flow = [];

        case 'LKDoG'
            % TODO: LK with Difference of Gaussian
            % opticFlow = opticalFlowLKDoG;
            % flow = estimateFlow(opticFlow, currGray);
            flow = [];

        otherwise
            error('不支持的光流方法: %s', params.method);
    end

    elapsed = toc(t_start);
    diagnostics = struct('method', params.method, 'elapsed_ms', elapsed * 1000);
end
