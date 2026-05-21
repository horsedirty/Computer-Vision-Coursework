%% phase_worker.m —— parfeval 后台处理函数
% 编码规范：参见项目根目录 AGENTS.md
% 角色七负责实现
%
% 功能：作为 parfeval 调用的后台 Worker，串联三阶段流水线。
% 通过 DataQueue 将帧更新推回 GUI，通过 PollableDataQueue 接收暂停信号。
% 参考论文 14_LightStab (CVPR 2026) 第 3.1 节多线程异步架构。
%
% INPUT:
%   videoPath       - 视频文件路径
%   motionParams    - 模块一参数 struct
%   smoothParams    - 模块二参数 struct
%   synthParams     - 模块三参数 struct
%   frameQueue      - parallel.pool.DataQueue，向 GUI 推送帧数据
%   pauseQueue      - parallel.pool.PollableDataQueue，接收暂停信号
%   diagQueue       - parallel.pool.DataQueue，向 GUI 推送诊断数据
%   startFrame      - 起始帧号
%   maxFrames       - 最大处理帧数
%   outputPath      - 输出视频路径
%
% OUTPUT:
%   无显式输出。所有结果通过 frameQueue / diagQueue 推送到 GUI。
%
% 调用关系：
%   run_motion_estimation → run_motion_smoothing → run_frame_synthesis
%   全部复用 src/ 下已有函数，本文件仅做流程编排。

function phase_worker(videoPath, motionParams, smoothParams, synthParams, ...
        frameQueue, pauseQueue, diagQueue, startFrame, maxFrames, outputPath)
    arguments
        videoPath (1,:) char
        motionParams struct = struct()
        smoothParams struct = struct()
        synthParams struct = struct()
        frameQueue = []
        pauseQueue = []
        diagQueue = []
        startFrame (1,1) double = 1
        maxFrames (1,1) double = Inf
        outputPath (1,:) char = ''
    end

    % ================================================================
    % 初始化：读取视频元信息
    % ================================================================
    vReader = VideoReader(videoPath);
    N_total = vReader.NumFrames;
    if isinf(maxFrames)
        N = N_total - startFrame + 1;
    else
        N = min(maxFrames, N_total - startFrame + 1);
    end

    % 发送视频元信息到 GUI
    sendDiag(diagQueue, struct('type', 'metadata', ...
        'totalFrames', N, 'fps', vReader.FrameRate, ...
        'width', vReader.Width, 'height', vReader.Height));

    % 预分配
    T_raw_seq = zeros(3, 3, N);
    T_raw_seq(:, :, 1) = eye(3);
    T_smoothed_seq = zeros(3, 3, N);

    % ================================================================
    % 阶段一：运动估计（逐帧，模块一）
    % ================================================================
    sendDiag(diagQueue, struct('type', 'phase', 'phase', 1, 'status', 'start'));
    sendFrame(frameQueue, struct('phase', 1, 'frame', read(vReader, startFrame), 'idx', 1, 'N', N));

    prevFrame = read(vReader, startFrame);

    for i = 2:N
        checkPause(pauseQueue);

        frameIdx = startFrame + i - 1;
        currFrame = read(vReader, frameIdx);

        [T_curr, diagMotion] = run_motion_estimation(prevFrame, currFrame, motionParams);
        T_raw_seq(:, :, i) = T_curr;

        sendFrame(frameQueue, struct('phase', 1, 'frame', currFrame, ...
            'idx', i, 'inlierRatio', diagMotion.inlier_ratio, 'N', N));

        prevFrame = currFrame;
    end

    sendDiag(diagQueue, struct('type', 'phase', 'phase', 1, 'status', 'done'));

    % ================================================================
    % 阶段二：运动分解与平滑（批量，模块二）
    % ================================================================
    sendDiag(diagQueue, struct('type', 'phase', 'phase', 2, 'status', 'start'));

    [T_smoothed_seq, paramHistory, diagSmooth] = run_motion_smoothing(T_raw_seq, smoothParams);

    sendDiag(diagQueue, struct('type', 'phase', 'phase', 2, 'status', 'done', ...
        'strategy', diagSmooth.smooth_strategy, 'smoothTimeMs', diagSmooth.total_time_ms));

    % 发送轨迹数据供可视化
    sendDiag(diagQueue, struct('type', 'trajectory', ...
        'T_raw_seq', T_raw_seq, 'T_smoothed_seq', T_smoothed_seq));

    % ================================================================
    % 阶段三：帧合成与去模糊（逐帧，模块三）
    % ================================================================
    sendDiag(diagQueue, struct('type', 'phase', 'phase', 3, 'status', 'start'));

    % 准备输出视频写入器
    synthProcessor = struct();
    synthProcessor.stabFrames = cell(N, 1);
    synthProcessor.vWriter = [];

    if ~isempty(outputPath)
        firstFrame = read(vReader, startFrame);
        synthProcessor.vWriter = VideoWriter(outputPath, 'MPEG-4');
        synthProcessor.vWriter.FrameRate = vReader.FrameRate;
        open(synthProcessor.vWriter);
    end

    for i = 1:N
        checkPause(pauseQueue);

        frameIdx = startFrame + i - 1;
        rawFrame = read(vReader, frameIdx);

        [stabFrame, ~, diagSynth] = run_frame_synthesis(...
            rawFrame, T_smoothed_seq(:, :, i), T_raw_seq(:, :, i), i, synthParams);

        % 写入输出视频
        if ~isempty(outputPath)
            writeVideo(synthProcessor.vWriter, stabFrame);
        end

        % 收集帧用于评估
        synthProcessor.stabFrames{i} = stabFrame;

        % 向后兼容：评估尚不可用时发送占位值
        psnrVal = NaN;
        ssimVal = NaN;
        if i > 1 && ~isempty(synthProcessor.stabFrames{i-1})
            try
                psnrVal = psnr(stabFrame, synthProcessor.stabFrames{i-1});
                ssimVal = ssim(stabFrame, synthProcessor.stabFrames{i-1});
            catch
            end
        end

        sendFrame(frameQueue, struct('phase', 3, 'frame', stabFrame, ...
            'idx', i, 'N', N, ...
            'warpTimeMs', diagSynth.warp_time_ms, ...
            'deblurApplied', diagSynth.deblur_applied, ...
            'psnr', psnrVal, 'ssim', ssimVal));
    end

    if ~isempty(synthProcessor.vWriter)
        close(synthProcessor.vWriter);
    end

    % 发送原始帧序列供评估
    rawFrames = cell(N, 1);
    for i = 1:N
        rawFrames{i} = read(vReader, startFrame + i - 1);
    end

    sendDiag(diagQueue, struct('type', 'phase', 'phase', 3, 'status', 'done'));

    % ================================================================
    % 全部完成
    % ================================================================
    sendDiag(diagQueue, struct('type', 'done', 'outputPath', outputPath, ...
        'rawFrames', {rawFrames}, 'stabFrames', {synthProcessor.stabFrames}));
end


%% 辅助函数：检查暂停
function checkPause(pauseQueue)
    if isempty(pauseQueue)
        return;
    end
    [msg, ok] = poll(pauseQueue, 0);
    if ok && strcmp(msg, 'pause')
        waitForResume(pauseQueue);
    end
end

function waitForResume(pauseQueue)
    while true
        [msg, ok] = poll(pauseQueue, 1);
        if ok && strcmp(msg, 'resume')
            return;
        end
    end
end


%% 辅助函数：发送帧数据
function sendFrame(queue, data)
    if isempty(queue)
        return;
    end
    try
        send(queue, data);
    catch
        % 队列可能已关闭，忽略
    end
end


%% 辅助函数：发送诊断数据
function sendDiag(queue, data)
    if isempty(queue)
        return;
    end
    try
        send(queue, data);
    catch
    end
end
