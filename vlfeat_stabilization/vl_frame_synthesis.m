function [diagnostics] = vl_frame_synthesis(videoObj, T_smoothed, T_raw_seq, outputPath, params)
    % VL_FRAME_SYNTHESIS 应用平滑后的变换矩阵进行帧重排并导出视频
    % 如果开启了 deblur，还会在 warp 之前使用 T_raw_seq 估算 PSF 并进行去卷积。
    
    arguments
        videoObj
        T_smoothed (3,3,:) double
        T_raw_seq (3,3,:) double
        outputPath (1,:) char
        params struct = struct()
    end
    
    if ~isfield(params, 'enable_deblur'), params.enable_deblur = false; end
    if ~isfield(params, 'enable_sharpen'), params.enable_sharpen = true; end
    if ~isfield(params, 'exposure_fraction'), params.exposure_fraction = 0.5; end
    if ~isfield(params, 'nsr'), params.nsr = 0.01; end
    if ~isfield(params, 'crop_ratio'), params.crop_ratio = 0; end
    if ~isfield(params, 'resize_to_original'), params.resize_to_original = false; end
    
    tic;
    numFrames = size(T_smoothed, 3);
    videoObj.CurrentTime = 0;
    
    % 如果开启了裁剪，提前计算裁剪矩形区域
    if params.crop_ratio > 0
        crop_x = round(videoObj.Width * params.crop_ratio) + 1;
        crop_y = round(videoObj.Height * params.crop_ratio) + 1;
        crop_w = videoObj.Width - 2 * (crop_x - 1);
        crop_h = videoObj.Height - 2 * (crop_y - 1);
        % 确保长宽是 16 的倍数 (Mac 上的 MPEG-4 硬件编码器对非 16 像素对齐的视频帧会产生内存步长/画面撕裂错误)
        crop_w = floor(crop_w / 16) * 16;
        crop_h = floor(crop_h / 16) * 16;
        crop_rect = [crop_x, crop_y, crop_w - 1, crop_h - 1];
    end
    
    v = VideoWriter(outputPath, 'MPEG-4');
    v.FrameRate = videoObj.FrameRate;
    open(v);
    
    for i = 1:numFrames
        if ~hasFrame(videoObj), break; end
        frame = readFrame(videoObj);
        
        % 如果开启了去模糊，先利用原始轨迹估计帧的运动模糊，并应用维纳滤波
        if params.enable_deblur
            % 注意：由于 T_raw_seq(:,:,i) 表示当前帧 i 到前一帧 i-1 的运动
            T_raw = T_raw_seq(:,:,i);
            dx = T_raw(3,1);
            dy = T_raw(3,2);
            motion_mag = sqrt(dx^2 + dy^2);
            
            % --- 自适应参数调节核心逻辑 ---
            % 既然脚本模拟包含了真实的运动模糊，我们直接采用设定的比例！
            adaptive_exp = params.exposure_fraction;
            adaptive_nsr = params.nsr;
            
            PSF = vl_estimate_blur_kernel(T_raw, adaptive_exp);
            frame = vl_wiener_deblur(frame, PSF, adaptive_nsr);
        end
        
        T = T_smoothed(:,:,i);
        tform = affine2d(T);
        
        % 视窗保持原样
        R = imref2d([videoObj.Height, videoObj.Width]);
        
        % Warp 图像：使用 'cubic' (双三次插值) 避免默认的线性插值模糊
        stabilizedFrame = imwarp(frame, tform, 'cubic', 'OutputView', R, 'FillValues', 0);
        
        % 裁剪边缘去黑边
        if params.crop_ratio > 0
            stabilizedFrame = imcrop(stabilizedFrame, crop_rect);
            % 如果用户需要，强制放大回原分辨率 (会带来一些放大模糊)
            if params.resize_to_original
                stabilizedFrame = imresize(stabilizedFrame, [videoObj.Height, videoObj.Width], 'bicubic');
            end
        end
        
        % 针对插值导致的轻微模糊，进行一次 USM 锐化补偿
        if params.enable_sharpen
            stabilizedFrame = imsharpen(stabilizedFrame, 'Amount', 1.0, 'Radius', 1.5);
        end
        
        writeVideo(v, stabilizedFrame);
    end
    
    close(v);
    diagnostics.total_time_ms = toc * 1000;
end
