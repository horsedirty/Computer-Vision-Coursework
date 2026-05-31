function vl_phase_worker(videoPath, smoothParams, synthParams, frameQueue, pauseQueue, diagQueue, startFrame, endFrame, outputPath)
    % VL_PHASE_WORKER 用于后台并行执行 VLFeat 防抖流水线的 worker 函数
    %
    % 与 GUI 进行通信的通道：
    %   frameQueue - 发送每一帧处理结果 (阶段1和阶段3)，更新左右预览窗口
    %   pauseQueue - 用于检查暂停状态 (可选)
    %   diagQueue  - 用于发送阶段状态、轨迹数据和完成状态
    
    % 1. 配置环境
    setup_vlfeat();
    
    videoObj = VideoReader(videoPath);
    
    % 发送阶段一进度
    if ~isempty(diagQueue)
        send(diagQueue, struct('type', 'phase', 'phase', 1, 'status', 'start'));
    end
    
    % ==============================================
    % 阶段一: 运动估计 (SIFT)
    % ==============================================
    % 注: 我们在底层 vl_motion_estimation 中已经添加了 frameQueue 以更新界面
    [T_sequence, diag_est] = vl_motion_estimation(videoObj, frameQueue, diagQueue);
    
    if ~isempty(diagQueue)
        send(diagQueue, struct('type', 'phase', 'phase', 1, 'status', 'done'));
    end
    
    % ==============================================
    % 阶段二: 运动平滑 (绝对高斯滤波)
    % ==============================================
    if ~isempty(diagQueue)
        send(diagQueue, struct('type', 'phase', 'phase', 2, 'status', 'start'));
    end
    
    windowSize = smoothParams.smooth_params.window_radius;
    [T_smoothed, diag_smooth] = vl_motion_smoothing(T_sequence, windowSize);
    
    if ~isempty(diagQueue)
        send(diagQueue, struct('type', 'trajectory', 'T_raw_seq', T_sequence, 'T_smoothed_seq', T_smoothed));
        send(diagQueue, struct('type', 'phase', 'phase', 2, 'status', 'done', 'strategy', 'Gaussian (Absolute)'));
    end
    
    % ==============================================
    % 阶段三: 帧合成与去模糊
    % ==============================================
    if ~isempty(diagQueue)
        send(diagQueue, struct('type', 'phase', 'phase', 3, 'status', 'start'));
    end
    
    % 重置 videoObj 时间
    videoObj.CurrentTime = 0;
    
    % 合成并输出
    vl_frame_synthesis(videoObj, T_smoothed, T_sequence, outputPath, synthParams, frameQueue, diagQueue);
    
    if ~isempty(diagQueue)
        send(diagQueue, struct('type', 'phase', 'phase', 3, 'status', 'done'));
        send(diagQueue, struct('type', 'done'));
    end
end
