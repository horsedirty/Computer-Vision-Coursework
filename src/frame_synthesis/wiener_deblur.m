% wiener_deblur.m —— 频域维纳去卷积
% 编码规范：参见项目根目录 AGENTS.md
% 角色六负责实现
%
% 功能：对 warp 后的帧做频域去模糊处理，支持三种去卷积方法。
% 在 YCbCr 色彩空间的亮度通道上执行去模糊，保留色彩信息不变。
%
% 维纳滤波公式（频域）：
%   F̂(u,v) = [H*(u,v) / (|H(u,v)|² + K)] · G(u,v)
%   其中 G = FFT{模糊图像}, H = FFT{PSF}, K = NSR（噪信比）
%   K 越大 → 去模糊越保守 → 抑制伪影但细节恢复较少
%
% 参考论文：16_CompEvent（频域处理思路、维纳滤波实现）
%          12_门控时空注意力（清晰度评估指标）
%          07_GoPro（去模糊评估范式）
%
% INPUT:
%   blurryFrame - warp 后的模糊帧，uint8 H×W×3 或 H×W
%   psf         - 模糊核 PSF（由 estimate_blur_kernel 输出）
%                 可以是方阵或标量 1（无模糊）
%   params      - 参数字典
%     .nsr       - 噪信比 (Noise-to-Signal Ratio)，默认 0.01
%                 数值越大越保守，推荐范围 [0, 0.1]
%     .method    - 去模糊方法: 'wiener' | 'lucy' | 'blind'
%                 默认 'wiener'
%     .padSize   - FFT 补零大小（避免频域边界效应）
%                 默认 []（自动使用图像尺寸）
%     .lucyIters - Lucy-Richardson 迭代次数，默认 10
%     .blindIters- Blind 去卷积迭代次数，默认 15
%     .sharpSkip - 清晰度跳过阈值：若 sharpnessBefore > sharpSkip
%                 则跳过去模糊（图像已足够清晰），默认 Inf（不跳过）
%
% OUTPUT:
%   deblurredFrame - uint8，去模糊后的帧（同尺寸）
%   diagnostics    - struct
%     .sharpness_before - 去模糊前拉普拉斯方差
%     .sharpness_after  - 去模糊后拉普拉斯方差
%     .sharpness_gain   - 清晰度提升比（>1 表示提升）
%     .method_used      - 实际使用的方法
%     .nsr_used         - 实际使用的 NSR
%     .skipped          - 是否因足够清晰而跳过

function [deblurredFrame, diagnostics] = wiener_deblur(blurryFrame, psf, params)
    arguments
        blurryFrame (:,:) uint8
        psf
        params struct = struct()
    end

    method     = safeField(params, 'method', 'wiener');
    nsr        = safeField(params, 'nsr', 0.01);
    lucyIters  = safeField(params, 'lucyIters', 10);
    blindIters = safeField(params, 'blindIters', 15);
    sharpSkip  = safeField(params, 'sharpSkip', Inf);

    t_start = tic;

    % ================================================================
    % 步骤 0: 快速退出检查
    % 如果 PSF 为标量 1，表示无模糊，直接返回
    % ================================================================
    if isscalar(psf) && abs(psf - 1) < 1e-9
        deblurredFrame = blurryFrame;
        sharpnessVal = estimate_sharpness(blurryFrame);
        diagnostics = struct(...
            'sharpness_before', sharpnessVal, ...
            'sharpness_after', sharpnessVal, ...
            'sharpness_gain', 1.0, ...
            'method_used', 'none', ...
            'nsr_used', 0, ...
            'skipped', true, ...
            'deblur_time_ms', toc(t_start) * 1000);
        return;
    end

    % ================================================================
    % 步骤 1: 模糊度评估（预处理）
    % 拉普拉斯方差：帧经 Laplacian 滤波后的像素方差
    % 数值越低 → 越模糊；越高 → 越清晰
    % 参考论文 12_门控时空注意力中的清晰度指标
    % ================================================================
    sharpnessBefore = estimate_sharpness(blurryFrame);

    if sharpnessBefore > sharpSkip
        deblurredFrame = blurryFrame;
        diagnostics = struct(...
            'sharpness_before', sharpnessBefore, ...
            'sharpness_after', sharpnessBefore, ...
            'sharpness_gain', 1.0, ...
            'method_used', 'skipped', ...
            'nsr_used', nsr, ...
            'skipped', true, ...
            'deblur_time_ms', toc(t_start) * 1000);
        return;
    end

    % ================================================================
    % 步骤 2: 色彩空间处理
    % 去模糊仅在亮度通道执行，保留色度通道不变
    % 原因：人眼对亮度敏感度远高于色度，且色度通道去模糊容易引入伪影
    % ================================================================
    [~, ~, nChannels] = size(blurryFrame);
    if nChannels == 3
        ycbcr = rgb2ycbcr(blurryFrame);
        Y = double(ycbcr(:,:,1));
        isColor = true;
    else
        Y = double(blurryFrame);
        isColor = false;
    end

    % ================================================================
    % 步骤 3: 准备 PSF（补齐到与图像匹配的尺寸）
    % deconvwnr 需要 PSF 与图像尺寸兼容
    % ================================================================
    psfMat = prepare_psf(psf, size(Y));

    % ================================================================
    % 步骤 4: 执行去卷积
    % ================================================================
    switch method
        case 'wiener'
            deblurredY = deconvwnr(Y, psfMat, nsr);

        case 'lucy'
            deblurredY = deconvlucy(Y, psfMat, lucyIters);

        case 'blind'
            psfInit = psfMat;
            if all(size(psfInit) > [31, 31])
                psfInit = imresize(psfInit, [31, 31]);
                psfInit = psfInit / sum(psfInit(:));
            end
            [deblurredY, ~] = deconvblind(Y, psfInit, blindIters);

        otherwise
            error('不支持的去模糊方法: %s。可选: wiener, lucy, blind', method);
    end

    % ================================================================
    % 步骤 5: 裁剪值域并重建图像
    % ================================================================
    deblurredY = clip(deblurredY, 0, 255);

    if isColor
        ycbcr(:,:,1) = uint8(deblurredY);
        deblurredFrame = ycbcr2rgb(ycbcr);
    else
        deblurredFrame = uint8(deblurredY);
    end

    % ================================================================
    % 步骤 6: 清晰度评估（后处理）
    % ================================================================
    sharpnessAfter = estimate_sharpness(deblurredFrame);
    sharpnessGain = sharpnessAfter / max(sharpnessBefore, 1e-6);

    elapsed = toc(t_start);

    diagnostics = struct(...
        'sharpness_before', sharpnessBefore, ...
        'sharpness_after', sharpnessAfter, ...
        'sharpness_gain', sharpnessGain, ...
        'method_used', method, ...
        'nsr_used', nsr, ...
        'skipped', false, ...
        'deblur_time_ms', elapsed * 1000);
end


%% ====== 局部辅助函数 ======

function sharpness = estimate_sharpness(frame)
    % 使用拉普拉斯方差作为清晰度指标
    % 先灰度化，再应用 Laplacian 滤波器，计算像素方差
    % 参考：Pech-Pacheco et al. (2000) 拉普拉斯方差无参考模糊度量
    if size(frame, 3) == 3
        grayFrame = rgb2gray(frame);
    else
        grayFrame = frame;
    end

    laplacianKernel = fspecial('laplacian', 0.2);
    lapResponse = imfilter(double(grayFrame), laplacianKernel, 'symmetric', 'same', 'conv');
    sharpness = var(lapResponse(:));
end


function psfMat = prepare_psf(psf, imageSize)
    % 确保 PSF 矩阵尺寸与图像兼容
    % deconvwnr 内部会将 PSF 补零到图像大小
    % 但显式准备可以避免 MATLAB 自动扩展时的警告
    if isscalar(psf)
        psfMat = psf;
        return;
    end

    psfMat = double(psf);

    % PSF 尺寸需要是奇数（fspecial('motion') 已保证这一点）
    % 移除 PSF 边缘几近为 0 的行/列，加速计算
    psfSum = sum(psfMat, 1);
    nonZeroCols = psfSum > max(psfSum) * 1e-6;
    psfSum = sum(psfMat, 2);
    nonZeroRows = psfSum > max(psfSum) * 1e-6;

    if any(nonZeroCols) && any(nonZeroRows)
        colIdx = find(nonZeroCols);
        rowIdx = find(nonZeroRows);
        psfMat = psfMat(rowIdx(1):rowIdx(end), colIdx(1):colIdx(end));
    end

    % 确保 PSF 不超过图像尺寸
    [psfH, psfW] = size(psfMat);
    if psfH > imageSize(1) || psfW > imageSize(2)
        psfMat = imresize(psfMat, min(imageSize(1), 31) * [1, 1]);
    end

    psfMat = psfMat / sum(psfMat(:));
end


function y = clip(x, lo, hi)
    y = max(min(x, hi), lo);
end


function val = safeField(s, fieldname, default)
    if isfield(s, fieldname)
        val = s.(fieldname);
    else
        val = default;
    end
end


%% ====== 自测 ======
% 对合成模糊图像测试维纳去模糊：
% original = imread('peppers.png');
% original = im2gray(original);
% psf = fspecial('motion', 15, 30);
% blurred = imfilter(double(original), psf, 'conv', 'circular');
% blurred = uint8(blurred);
% params = struct('method', 'wiener', 'nsr', 0.01);
% [deblurred, diag] = wiener_deblur(blurred, psf, params);
% subplot(1,3,1); imshow(original); title('Original');
% subplot(1,3,2); imshow(blurred); title(sprintf('Blurred (lap=%.0f)', diag.sharpness_before));
% subplot(1,3,3); imshow(deblurred); title(sprintf('Deblurred (lap=%.0f)', diag.sharpness_after));
% fprintf('清晰度提升: %.2fx\n', diag.sharpness_gain);
