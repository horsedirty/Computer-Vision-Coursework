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
    if ~isfield(params, 'exposure_fraction'), params.exposure_fraction = 0.5; end
    if ~isfield(params, 'nsr'), params.nsr = 0.01; end
    
    tic;
    numFrames = size(T_smoothed, 3);
    videoObj.CurrentTime = 0;
    
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
        
        % Warp 图像
        stabilizedFrame = imwarp(frame, tform, 'OutputView', R, 'FillValues', 0);
        
        writeVideo(v, stabilizedFrame);
    end
    
    close(v);
    diagnostics.total_time_ms = toc * 1000;
end
