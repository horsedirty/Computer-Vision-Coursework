%% analyze_failure_cases.m —— 失败案例分析
% 编码规范：参见项目根目录 AGENTS.md
% 角色八负责实现
%
% 功能：分析稳定化失败或质量较差的帧，定位问题原因。
% 通过逐帧计算帧间变换幅度、平滑残差、帧合成质量等指标，
% 标记异常帧并生成诊断报告。
%
% 检测维度：
%   1. 大位移突变帧 —— |T_raw| 与局部均值的偏差
%   2. 平滑过度帧  —— |T_smoothed - T_raw| 过大
%   3. 合成质量差帧 —— 运动模糊估计失败（diag 中有错误记录）
%
% INPUT:
%   diagPath       - 诊断文件路径 (.mat)
%   params         - 参数字典
%     .analysisPath  - 输出报告保存路径，默认 ''
%     .threshold_large_motion  - 大位移阈值 (倍标准差)，默认 2.5
%     .threshold_over_smooth   - 过平滑阈值 (倍标准差)，默认 2.0
%     .topN                    - 返回最差的 topN 帧，默认 5
%     .verbose                 - 是否打印详情，默认 true
%
% OUTPUT:
%   report         - struct，包含
%     .largeMotionFrames   - 大位移突变帧列表
%     .overSmoothFrames    - 过度平滑帧列表
%     .lowQualityFrames    - 合成质量差帧列表
%     .perFrameStats       - 每帧统计表
%     .summary             - 字符串摘要

function report = analyze_failure_cases(diagPath, params)
    arguments
        diagPath (1,:) char
        params struct = struct()
    end

    if ~isfield(params, 'analysisPath'),             params.analysisPath = ''; end
    if ~isfield(params, 'threshold_large_motion'),   params.threshold_large_motion = 2.5; end
    if ~isfield(params, 'threshold_over_smooth'),    params.threshold_over_smooth = 2.0; end
    if ~isfield(params, 'topN'),                     params.topN = 5; end
    if ~isfield(params, 'verbose'),                  params.verbose = true; end

    % 加载诊断文件
    if ~exist(diagPath, 'file')
        error('诊断文件不存在: %s', diagPath);
    end
    data = load(diagPath);

    if ~isfield(data, 'T_raw_seq')
        error('诊断文件中缺少 T_raw_seq 字段');
    end
    T_raw      = data.T_raw_seq;
    T_smoothed = safeField(data, 'T_smoothed_seq', T_raw);
    diag_motion = safeField(data, 'diag_motion', cell(size(T_raw,3), 1));
    diag_synth  = safeField(data, 'diag_synth',  cell(size(T_raw,3), 1));

    N = size(T_raw, 3);

    % 计算每帧的变换幅度 (Frobenius norm 与 I 的偏差)
    transMag = zeros(N, 1);
    smoothResidual = zeros(N, 1);
    hasSynthError = false(N, 1);

    I3 = eye(3);
    for i = 1:N
        % 变换幅度: 与单位矩阵的 Frobenius 距离
        transMag(i) = norm(T_raw(:,:,i) - I3, 'fro');

        % 平滑残差: 平滑前后变换矩阵的 Frobenius 距离
        if i <= size(T_smoothed, 3)
            smoothResidual(i) = norm(T_smoothed(:,:,i) - T_raw(:,:,i), 'fro');
        end

        % 合成错误检查
        if i <= numel(diag_synth) && ~isempty(diag_synth{i})
            if isstruct(diag_synth{i}) && isfield(diag_synth{i}, 'error')
                hasSynthError(i) = true;
            end
        end
    end

    % ---- 1. 大位移突变帧 ----
    % 计算局部滑动窗口（窗宽 5）的均值与标准差
    w      = 5;
    hw     = floor(w / 2);
    localMean = zeros(N, 1);
    localStd  = zeros(N, 1);
    for i = 1:N
        lo = max(1, i - hw);
        hi = min(N, i + hw);
        seg = transMag(lo:hi);
        localMean(i) = mean(seg);
        localStd(i)  = std(seg);
    end
    % 防止除零
    localStd(localStd < 1e-6) = 1e-6;
    anomalyScore_motion = (transMag - localMean) ./ localStd;
    largeMotionFrames = find(anomalyScore_motion > params.threshold_large_motion);

    % ---- 2. 过度平滑帧 ----
    if N > 1
        meanResid = mean(smoothResidual);
        stdResid  = std(smoothResidual);
        if stdResid < 1e-6, stdResid = 1e-6; end
        anomalyScore_smooth = (smoothResidual - meanResid) ./ stdResid;
    else
        anomalyScore_smooth = zeros(N, 1);
    end
    overSmoothFrames = find(anomalyScore_smooth > params.threshold_over_smooth);

    % ---- 3. 合成质量差帧 ----
    lowQualityFrames = find(hasSynthError);

    % ---- 4. 综合 Top-N ----
    compositeScore = anomalyScore_motion + anomalyScore_smooth;
    compositeScore(hasSynthError) = compositeScore(hasSynthError) + 5; % 惩罚有错误的帧
    [~, worstIdx] = sort(compositeScore, 'descend');
    topN = min(params.topN, N);
    worstFrames = worstIdx(1:topN);

    % 构建输出
    report.largeMotionFrames = largeMotionFrames(:);
    report.overSmoothFrames  = overSmoothFrames(:);
    report.lowQualityFrames  = lowQualityFrames(:);
    report.worstFrames       = worstFrames(:);
    report.anomalyScore_motion  = anomalyScore_motion;
    report.anomalyScore_smooth  = anomalyScore_smooth;
    report.compositeScore       = compositeScore;
    report.transMag             = transMag;
    report.smoothResidual       = smoothResidual;

    % 构建摘要
    report.summary = sprintf([ ...
        '==== 失败案例分析报告 ====\n', ...
        '诊断文件: %s\n', ...
        '总帧数: %d\n', ...
        '大位移突变帧: %d 帧 (%.1f%%)\n', ...
        '过度平滑帧:   %d 帧 (%.1f%%)\n', ...
        '合成质量差帧:  %d 帧 (%.1f%%)\n', ...
        '最差 %d 帧索引: %s\n', ...
        '===============================\n'], ...
        diagPath, N, ...
        numel(largeMotionFrames), numel(largeMotionFrames)/N*100, ...
        numel(overSmoothFrames),  numel(overSmoothFrames)/N*100, ...
        numel(lowQualityFrames),  numel(lowQualityFrames)/N*100, ...
        topN, mat2str(worstFrames(:)');

    if params.verbose
        fprintf(report.summary);
    end

    % 保存报告
    if ~isempty(params.analysisPath)
        [outDir, ~, ~] = fileparts(params.analysisPath);
        if ~exist(outDir, 'dir'), mkdir(outDir); end
        save(params.analysisPath, 'report');
        fprintf('失败案例分析报告已保存: %s\n', params.analysisPath);
    end
end

%% 辅助函数
function val = safeField(s, fname, defaultVal)
    if isfield(s, fname)
        val = s.(fname);
    else
        val = defaultVal;
    end
end
