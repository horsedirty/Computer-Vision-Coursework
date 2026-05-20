%% wiener_deblur.m —— 频域维纳去卷积
% 编码规范：参见项目根目录 AGENTS.md
% 角色六负责实现
%
% 功能：对 warp 后的帧做频域维纳滤波去模糊。
% 频域处理的优势：去卷积在频域中是逐点除法，比空间域卷积高效得多。
%
% 维纳滤波公式：
%   F̂(u,v) = [H*(u,v) / (|H(u,v)|² + K)] · G(u,v)
%   其中 G = FFT{模糊图像}, H = FFT{PSF}, K = 噪声比
%
% 参考论文：16_CompEvent（频域处理思路）
%
% INPUT:
%   blurryFrame - warp 后的模糊帧，uint8 H×W×3 或单通道
%   psf         - 模糊核 PSF
%   params      - 参数字典
%     .nsr       - 噪信比 (Noise-to-Signal Ratio)，默认 0.01
%                 数值越大，去模糊越保守（越不容易出现伪影）
%     .method    - 'wiener' | 'lucy' | 'blind'，默认 'wiener'
%     .padSize   - FFT 补零大小（避免边界效应），默认 []（自动）
%
% OUTPUT:
%   deblurredFrame - uint8，去模糊后的帧（同尺寸）
%   diagnostics    - struct
%     .sharpness_gain  - 拉普拉斯方差提升比
%     .nsr_used        - 实际使用的 NSR

function [deblurredFrame, diagnostics] = wiener_deblur(blurryFrame, psf, params)
    arguments
        blurryFrame (:,:) uint8
        psf
        params struct = struct()
    end

    if ~isfield(params, 'nsr'),     params.nsr = 0.01; end
    if ~isfield(params, 'method'),  params.method = 'wiener'; end
    if ~isfield(params, 'padSize'), params.padSize = []; end

    t_start = tic;

    % === 模糊度评估（预处理） ===
    % TODO: 计算拉普拉斯方差作为清晰度指标
    % laplacian = fspecial('laplacian', 0.2);
    % sharpness_before = var(imfilter(double(rgb2gray(blurryFrame)), laplacian), [], 'all');

    % 如果几乎不模糊，跳过
    % if sharpness_before > some_threshold
    %     deblurredFrame = blurryFrame;
    %     diagnostics.sharpness_gain = 1.0;
    %     return;
    % end

    % === 灰度转换（去模糊在亮度通道上） ===
    if size(blurryFrame, 3) == 3
        ycbcr = rgb2ycbcr(blurryFrame);
        Y = double(ycbcr(:,:,1));
        isColor = true;
    else
        Y = double(blurryFrame);
        isColor = false;
    end

    % === 去卷积 ===
    switch params.method
        case 'wiener'
            % TODO: deblurred_Y = deconvwnr(Y, psf, params.nsr);
            % 如果 psf 是标量 1（无模糊），直接跳过
            deblurred_Y = Y;

        case 'lucy'
            % TODO:  Richardson-Lucy 迭代去卷积
            % deblurred_Y = deconvlucy(Y, psf, 10);  % 10 次迭代

        case 'blind'
            % TODO: 盲去卷积（连 PSF 也一起优化）
            % [deblurred_Y, ~] = deconvblind(Y, psf_init, 10);

        otherwise
            error('不支持的去模糊方法: %s', params.method);
    end

    % === 重建彩色图像 ===
    if isColor
        ycbcr(:,:,1) = uint8(clip(deblurred_Y, 0, 255));
        deblurredFrame = ycbcr2rgb(ycbcr);
    else
        deblurredFrame = uint8(clip(deblurred_Y, 0, 255));
    end

    % === 清晰度评估（后处理） ===
    % TODO: sharpness_after = var(imfilter(...));
    % sharpness_gain = sharpness_after / sharpness_before

    elapsed = toc(t_start);
    diagnostics = struct(...
        'method', params.method, ...
        'nsr', params.nsr, ...
        'sharpness_gain', 1.0, ...  % TODO
        'deblur_time_ms', elapsed * 1000);
end


%% 辅助函数：截断
function y = clip(x, lo, hi)
    y = max(min(x, hi), lo);
end
