function deblurred_frame = vl_wiener_deblur(frame, PSF, nsr)
    % VL_WIENER_DEBLUR 使用维纳滤波对图像进行非盲去卷积
    %
    % INPUT:
    %   frame - 原始模糊图像 (H x W x 3 uint8 或 single)
    %   PSF   - 点扩散函数，由 vl_estimate_blur_kernel 生成
    %   nsr   - 噪声信号比 (Noise-to-Signal Ratio)，用于控制锐化强度和抑制振铃
    %           值越小锐化越强，但更容易出现振铃；值越大越平滑。默认 0.01。
    %
    % OUTPUT:
    %   deblurred_frame - 去模糊后的图像 (uint8)
    
    arguments
        frame
        PSF (:,:) double
        nsr (1,1) double = 0.01
    end
    
    % 如果 PSF 是 1x1 的脉冲，说明没有模糊，直接返回
    if isscalar(PSF) && PSF == 1
        deblurred_frame = frame;
        return;
    end
    
    % 转换类型为 double 以防去卷积时溢出
    img = im2double(frame);
    
    % 强制使用 edgetaper 处理图像边缘，这是避免去卷积时产生全图水波纹 (Ringing Artifacts) 的关键！
    if size(img, 3) == 3
        img(:,:,1) = edgetaper(img(:,:,1), PSF);
        img(:,:,2) = edgetaper(img(:,:,2), PSF);
        img(:,:,3) = edgetaper(img(:,:,3), PSF);
    else
        img = edgetaper(img, PSF);
    end

    deblurred_img = zeros(size(img));
    
    if size(img, 3) == 3
        % 对 RGB 各个通道分别去卷积
        for c = 1:3
            deblurred_img(:,:,c) = deconvwnr(img(:,:,c), PSF, nsr);
        end
    else
        % 灰度图直接去卷积
        deblurred_img = deconvwnr(img, PSF, nsr);
    end
    
    % 恢复成 uint8 格式
    deblurred_frame = im2uint8(deblurred_img);
end
