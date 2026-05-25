%% main_pipeline.m —— 三阶段完整流水线
% 编码规范：参见项目根目录 AGENTS.md
% 项目负责人统筹，所有角色协作
%
% 功能：端到端的视频防抖去模糊处理流水线。
% 读取视频文件 → 逐帧运动估计 → 全局运动分解与平滑 → 帧合成与去模糊 → 输出稳定视频。
%
% 架构：
%   输入视频帧 ──▶ [模块一] 运动估计 ──▶ [模块二] 运动分解与平滑 ──▶ [模块三] 帧合成与去模糊 ──▶ 输出视频
%                     T_raw (3×3×N)          T_smoothed (3×3×N)          stabilizedFrames
%
% 使用说明：
%   1. 设置 params 中的 inputVideo 路径
%   2. 可选：调整个别模块参数（detect_params, smooth_params 等）
%   3. 运行 main_pipeline()
%   4. 输出视频保存在 data/results/ 下
%
% INPUT:
%   params - struct，全局参数字典
%     .inputVideo        - 输入视频路径（字符串），必填
%     .outputVideo       - 输出视频路径，默认 'data/results/stabilized.mp4'
%     .startFrame        - 起始帧号，默认 1
%     .maxFrames         - 最大处理帧数，默认 Inf（全部）
%     .motion_params     - 模块一参数
%     .smooth_params     - 模块二参数
%     .synthesis_params  - 模块三参数
%     .verbose           - 是否打印每帧日志，默认 true
%     .saveDiagnostics   - 是否保存诊断数据到 .mat，默认 true
%
% OUTPUT:
%   (无显式输出，结果写入 outputVideo 文件)
%   同时生成:
%     outputVideo             - 稳定视频 .mp4
%     outputVideo(1:end-4)_diag.mat - 诊断数据（每帧耗时、内点率等）
%
% 参考论文: 14_LightStab (CVPR2026), 17_在线拼接防抖 (MDPI2025)

function main_pipeline(params)
    arguments
        params struct
    end

    % ================================================================
    % 参数初始化
    % ================================================================
    if ~isfield(params, 'inputVideo') || isempty(params.inputVideo)
        error('请指定输入视频路径: params.inputVideo');
    end
    inputVideo  = params.inputVideo;

    outputVideo = safeField(params, 'outputVideo', ...
        fullfile('data', 'results', 'stabilized.mp4'));
    startFrame  = safeField(params, 'startFrame', 1);
    maxFrames   = safeField(params, 'maxFrames', Inf);
    verbose     = safeField(params, 'verbose', true);
    saveDiag    = safeField(params, 'saveDiagnostics', true);

    motion_params    = safeField(params, 'motion_params', struct());
    smooth_params    = safeField(params, 'smooth_params', struct());
    synthesis_params = safeField(params, 'synthesis_params', struct());

    % ================================================================
    % 第一步: 读取视频（第一遍遍历，收集变换矩阵）
    % ================================================================
    if verbose, fprintf('[Pipeline] 加载视频: %s\n', inputVideo); end

    vReader = VideoReader(inputVideo);
    N_total = vReader.NumFrames;
    if isinf(maxFrames)
        N = N_total - startFrame + 1;
    else
        N = min(maxFrames, N_total - startFrame + 1);
    end
    if verbose, fprintf('[Pipeline] 总帧数: %d, 处理帧数: %d, 帧率: %.2f fps\n', N_total, N, vReader.FrameRate); end

    % 预分配
    T_raw_seq      = zeros(3, 3, N);
    T_smoothed_seq = zeros(3, 3, N);

    % 诊断记录
    diag_motion   = cell(N, 1);
    diag_smooth   = [];
    diag_synth    = cell(N, 1);
    total_time_per_frame = zeros(N, 1);

    % ================================================================
    % 第二步: 第一遍遍历 —— 运动估计（模块一）
    %         对每一帧独立计算帧间变换矩阵，收集到 T_raw_seq
    % ================================================================
    if verbose, fprintf('[Pipeline] 阶段一: 运动估计...\n'); end

    % 读取第一帧作为初始参考
    prevFrame = read(vReader, startFrame);
    T_raw_seq(:,:,1) = eye(3);

    for i = 2:N
        frameIdx = startFrame + i - 1;
        currFrame = read(vReader, frameIdx);

        t_frame = tic;

        % --- 模块一: 运动估计 ---
        [T_curr, diag_motion{i}] = run_motion_estimation(prevFrame, currFrame, motion_params);
        T_raw_seq(:,:,i) = T_curr;

        total_time_per_frame(i) = toc(t_frame);

        if verbose && mod(i, 50) == 0
            fprintf('  帧 %d/%d | 内点率: %.2f | 耗时: %.1f ms\n', ...
                i, N, diag_motion{i}.inlier_ratio, total_time_per_frame(i)*1000);
        end

        prevFrame = currFrame;
    end

    if verbose
        mean_motion_time = mean(total_time_per_frame(2:end)) * 1000;
        fprintf('[Pipeline] 运动估计完成, 平均 %.1f ms/帧\n', mean_motion_time);
    end

    % ================================================================
    % 场景聚合：按 scene_type 汇总各检测器内点率
    % ================================================================
    sceneAgg = struct();
    for i = 2:N
        if ~isfield(diag_motion{i}, 'scene_type'), continue; end
        sceneType = diag_motion{i}.scene_type;
        if ~isfield(sceneAgg, sceneType)
            sceneAgg.(sceneType) = struct('count', 0);
        end
        sceneAgg.(sceneType).count = sceneAgg.(sceneType).count + 1;

        if ~isfield(diag_motion{i}, 'per_detector_stats'), continue; end
        pds = diag_motion{i}.per_detector_stats;
        detNames = fieldnames(pds);
        for d = 1:length(detNames)
            detName = detNames{d};
            if ~isfield(sceneAgg.(sceneType), detName)
                sceneAgg.(sceneType).(detName) = struct('total', 0, 'inlier', 0);
            end
            sceneAgg.(sceneType).(detName).total = ...
                sceneAgg.(sceneType).(detName).total + pds.(detName).total;
            sceneAgg.(sceneType).(detName).inlier = ...
                sceneAgg.(sceneType).(detName).inlier + pds.(detName).inlier;
        end
    end

    if verbose
        fprintf('\n[Pipeline] 各场景检测器内点率聚合:\n');
        sceneTypes = fieldnames(sceneAgg);
        for s = 1:length(sceneTypes)
            st = sceneTypes{s};
            fprintf('  [%s] %d帧\n', st, sceneAgg.(st).count);
            detNames = fieldnames(sceneAgg.(st));
            for d = 1:length(detNames)
                if strcmp(detNames{d}, 'count'), continue; end
                detName = detNames{d};
                t = sceneAgg.(st).(detName).total;
                il = sceneAgg.(st).(detName).inlier;
                rate = il / max(t, 1);
                fprintf('    %-8s total: %d, inlier: %d, rate: %.2f\n', ...
                    detName, t, il, rate);
            end
        end
        fprintf('\n');
    end

    % ================================================================
    % 第三步: 运动分解与平滑（模块二）
    %         输入 T_raw_seq，输出 T_smoothed_seq
    %         这一步是 BATCH 操作——整个序列的变换矩阵一次性处理
    % ================================================================
    if verbose, fprintf('[Pipeline] 阶段二: 运动分解与平滑 (%s)...\n', ...
        safeField(smooth_params, 'smooth_strategy', 'markov')); end

    [T_smoothed_seq, paramHistory, diag_smooth] = run_motion_smoothing(T_raw_seq, smooth_params);

    if verbose
        fprintf('[Pipeline] 运动平滑完成, 耗时 %.1f ms\n', diag_smooth.total_time_ms);
    end

    % ================================================================
    % 第四步: 第二遍遍历 —— 帧合成与去模糊（模块三）
    %         逐帧应用平滑后的变换，输出稳定帧
    % ================================================================
    if verbose, fprintf('[Pipeline] 阶段三: 帧合成与去模糊...\n'); end

    % 准备输出视频写入器
    firstFrame = read(vReader, startFrame);
    [H_out, W_out, ~] = size(firstFrame);
    vWriter = VideoWriter(outputVideo, 'MPEG-4');
    vWriter.FrameRate = vReader.FrameRate;
    open(vWriter);

    synth_times = zeros(N, 1);

    for i = 1:N
        frameIdx = startFrame + i - 1;
        rawFrame = read(vReader, frameIdx);

        t_synth = tic;

        % --- 模块三: 帧合成与去模糊 ---
        [stabFrame, ~, diag_synth{i}] = run_frame_synthesis(...
            rawFrame, T_smoothed_seq(:,:,i), T_raw_seq(:,:,i), i, synthesis_params);

        synth_times(i) = toc(t_synth);

        % 写入输出视频
        % 注意：stabFrame 可能被裁剪，需确保尺寸一致
        writeVideo(vWriter, stabFrame);

        if verbose && mod(i, 50) == 0
            fprintf('  输出帧 %d/%d | warp: %.1f ms | deblur: %s\n', ...
                i, N, diag_synth{i}.warp_time_ms, ...
                ternary(diag_synth{i}.deblur_applied, '✓', '-'));
        end
    end

    close(vWriter);

    if verbose
        mean_synth_time = mean(synth_times) * 1000;
        fprintf('[Pipeline] 帧合成完成, 平均 %.1f ms/帧\n', mean_synth_time);
    end

    % ================================================================
    % 第五步: 保存诊断数据
    % ================================================================
    overall_fps = N / sum(total_time_per_frame(2:end) + synth_times(2:end));

    fprintf('\n========== 处理完成 ==========\n');
    fprintf('输出视频: %s\n', outputVideo);
    fprintf('处理帧数: %d\n', N);
    fprintf('平均帧率: %.1f fps\n', overall_fps);
    fprintf('平滑策略: %s\n', diag_smooth.smooth_strategy);

    if saveDiag
        diagFile = [outputVideo(1:end-4) '_diag.mat'];
        save(diagFile, 'T_raw_seq', 'T_smoothed_seq', 'paramHistory', ...
            'diag_motion', 'diag_smooth', 'diag_synth', ...
            'total_time_per_frame', 'synth_times', 'overall_fps', 'sceneAgg');
        fprintf('诊断数据: %s\n', diagFile);
    end
end


%% 辅助函数
function val = safeField(s, fieldname, default)
    if isfield(s, fieldname)
        val = s.(fieldname);
    else
        val = default;
    end
end

function s = ternary(cond, t, f)
    if cond, s = t; else, s = f; end
end
