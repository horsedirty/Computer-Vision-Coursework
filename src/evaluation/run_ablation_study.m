%% run_ablation_study.m —— 消融实验自动化
% 编码规范：参见项目根目录 AGENTS.md
% 角色八负责实现
%
% 功能：自动在指定测试视频上运行多组参数组合，
% 收集并汇总评估指标（PSNR, SSIM, SR, FPS），输出实验表格。
%
% 消融维度（对应论文 17, 14, 12 的技术贡献）:
%   1. 检测器选择:  SIFT 单检测器 vs SIFT+SURF 双检测器
%   2. 平滑策略:    高斯 → 相对坐标高斯 → 相对坐标马尔可夫
%   3. 去模糊:      无去模糊 vs 维纳去卷积
%   4. 窗口半径:    l=1 vs l=3 vs l=5
%
% INPUT:
%   inputVideo      - 测试视频路径
%   params          - 参数字典
%     .ablations      - cell array of struct，每个包含要覆盖的参数
%                       若未提供，使用默认消融矩阵
%     .saveResults    - 是否保存 .mat 结果，默认 true
%     .outputCSV      - 是否导出 CSV 表格，默认 true
%
% OUTPUT:
%   resultsTable    - table，行=实验条件、列=指标
%   allResults      - cell array，每次实验的完整诊断数据

function [resultsTable, allResults] = run_ablation_study(inputVideo, params)
    arguments
        inputVideo char
        params struct = struct()
    end

    if ~isfield(params, 'ablations'),    params.ablations = get_default_ablations(); end
    if ~isfield(params, 'saveResults'),  params.saveResults = true; end
    if ~isfield(params, 'outputCSV'),    params.outputCSV = true; end

    ablations = params.ablations;
    nExp = numel(ablations);
    allResults = cell(nExp, 1);

    % 结果表格预分配
    expNames = cell(nExp, 1);
    psnrVals = zeros(nExp, 1);
    ssimVals = zeros(nExp, 1);
    srVals   = zeros(nExp, 1);
    fpsVals  = zeros(nExp, 1);
    motionTime = zeros(nExp, 1);
    smoothTime = zeros(nExp, 1);
    synthTime  = zeros(nExp, 1);

    fprintf('========== 消融实验 ==========\n');
    fprintf('测试视频: %s\n', inputVideo);
    fprintf('实验数量: %d\n\n', nExp);

    for e = 1:nExp
        fprintf('--- 实验 %d/%d: %s ---\n', e, nExp, ablations{e}.name);

        % 构建本实验参数
        expParams = build_pipeline_params(inputVideo, ablations{e});

        % 运行主流水线
        try
            main_pipeline(expParams);

            % TODO: 从诊断文件加载结果并计算指标
            % diagFile = [expParams.outputVideo(1:end-4) '_diag.mat'];
            % load(diagFile, 'T_raw_seq', 'T_smoothed_seq', 'diag_motion', 'diag_smooth', 'diag_synth', 'total_time_per_frame', 'synth_times');
            %
            % [psnrVals(e), ~, ssimVals(e), ~, ~] = compute_psnr_ssim(...);
            % [srVals(e), ~, ~, ~] = compute_stabilization_ratio(T_raw_seq, T_smoothed_seq);
            % N = size(T_raw_seq, 3);
            % fpsVals(e) = N / sum(total_time_per_frame(2:end) + synth_times(2:end));
            % motionTime(e) = mean(cellfun(@(d) d.total_time_ms, diag_motion(2:end)));
            % smoothTime(e) = diag_smooth.total_time_ms / N;
            % synthTime(e)  = mean(cellfun(@(d) d.total_time_ms, diag_synth));

        catch ME
            fprintf('  [警告] 实验失败: %s\n', ME.message);
            psnrVals(e) = NaN;
            ssimVals(e) = NaN;
            srVals(e) = NaN;
            fpsVals(e) = NaN;
        end

        expNames{e} = ablations{e}.name;
        fprintf('\n');
    end

    % === 汇总为 Table ===
    resultsTable = table(expNames, psnrVals, ssimVals, srVals, fpsVals, ...
        motionTime, smoothTime, synthTime, ...
        'VariableNames', {'实验条件', 'PSNR_dB', 'SSIM', 'SR', 'FPS', ...
                          '运动估计_ms', '平滑_ms', '帧合成_ms'});

    % === 展示 ===
    disp(resultsTable);

    % === 保存 ===
    if params.saveResults
        [~, name, ~] = fileparts(inputVideo);
        save(fullfile('data', 'results', [name '_ablation.mat']), 'resultsTable', 'allResults');
    end

    if params.outputCSV
        writetable(resultsTable, fullfile('data', 'results', [name '_ablation.csv']));
        fprintf('\n结果已导出: data/results/%s_ablation.csv\n', name);
    end
end


%% 默认消融实验矩阵
function ablations = get_default_ablations()
    ablations = {};

    % 实验 1: 基线（SIFT + 高斯绝对坐标 + 无去模糊）
    ablations{1} = struct('name', '基线_SIFT_高斯_无去模糊', ...
        'detect_method', 'SIFT', ...
        'smooth_strategy', 'gaussian_absolute', ...
        'enable_deblur', false);

    % 实验 2: SIFT+SURF 双检测器
    ablations{2} = struct('name', '双检测器_SIFT+SURF_高斯_无去模糊', ...
        'detect_method', 'SIFT+SURF', ...
        'smooth_strategy', 'gaussian_absolute', ...
        'enable_deblur', false);

    % 实验 3: 相对坐标高斯平滑
    ablations{3} = struct('name', 'SIFT_相对坐标高斯_无去模糊', ...
        'detect_method', 'SIFT', ...
        'smooth_strategy', 'gaussian_relative', ...
        'enable_deblur', false);

    % 实验 4: 完整版（马尔可夫 + 无去模糊）
    ablations{4} = struct('name', 'SIFT_马尔可夫_l=3_无去模糊', ...
        'detect_method', 'SIFT', ...
        'smooth_strategy', 'markov', ...
        'window_radius', 3, ...
        'enable_deblur', false);

    % 实验 5: 完整版 + 频域维纳去模糊
    ablations{5} = struct('name', 'SIFT_马尔可夫_l=3_维纳去模糊', ...
        'detect_method', 'SIFT', ...
        'smooth_strategy', 'markov', ...
        'window_radius', 3, ...
        'enable_deblur', true, ...
        'deblur_method', 'wiener');

    % 实验 6: 窗口半径 l=1
    ablations{6} = struct('name', 'SIFT_马尔可夫_l=1_无去模糊', ...
        'detect_method', 'SIFT', ...
        'smooth_strategy', 'markov', ...
        'window_radius', 1, ...
        'enable_deblur', false);

    % 实验 7: 窗口半径 l=5
    ablations{7} = struct('name', 'SIFT_马尔可夫_l=5_无去模糊', ...
        'detect_method', 'SIFT', ...
        'smooth_strategy', 'markov', ...
        'window_radius', 5, ...
        'enable_deblur', false);
end


%% 将消融实验描述转换为 main_pipeline 参数
function expParams = build_pipeline_params(inputVideo, ablation)
    expParams = struct();
    expParams.inputVideo = inputVideo;
    expParams.saveDiagnostics = true;

    % 输出文件命名为 {视频名}_{实验名}.mp4
    [~, videoName, ~] = fileparts(inputVideo);
    expName = strrep(ablation.name, ' ', '_');
    expParams.outputVideo = fullfile('data', 'results', [videoName '_' expName '.mp4']);

    % 模块一参数
    expParams.motion_params = struct();
    expParams.motion_params.detect_params = struct();
    % TODO: 根据 ablation.detect_method 设置
    % expParams.motion_params.use_sparse_fusion = ...

    % 模块二参数
    expParams.smooth_params = struct();
    expParams.smooth_params.smooth_strategy = ablation.smooth_strategy;
    if isfield(ablation, 'window_radius')
        expParams.smooth_params.smooth_params = struct('window_radius', ablation.window_radius);
    end

    % 模块三参数
    expParams.synthesis_params = struct();
    expParams.synthesis_params.enable_deblur = ablation.enable_deblur;
    if isfield(ablation, 'deblur_method')
        expParams.synthesis_params.deblur_params = struct('method', ablation.deblur_method);
    end
end
