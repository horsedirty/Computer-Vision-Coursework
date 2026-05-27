%% run_full_evaluation.m —— Comprehensive Evaluation Orchestrator
% Coding standard: See project root AGENTS.md
% Role 8 is responsible for implementation
%
% Function: One-click run of the complete evaluation pipeline, including:
%   1. Ablation study (run_ablation_study)
%   2. Module time pie chart (visualize_module_pie)
%   3. Ablation bar chart (visualize_ablation_bars)
%   4. Frame comparison visualization (visualize_frame_comparison)
%   5. Failure case analysis (analyze_failure_cases)
%   6. Generate Markdown evaluation report
%
% INPUT:
%   params  - Parameter dictionary
%     .inputVideo        - Input video path
%     .outputDir          - Output directory, default 'data/evaluation_results'
%     .ablationMatrix     - Custom ablation experiment matrix (optional)
%     .frameIndices       - Frame indices for comparison, default [1, 50, 100]
%     .skipAblation       - Whether to skip ablation study, default false
%     .verbose            - Whether to output verbose details, default true
%
% OUTPUT:
%   evalResults  - struct containing all evaluation results

function evalResults = run_full_evaluation(params)
    arguments
        params struct = struct()
    end

    if ~isfield(params, 'outputDir'),    params.outputDir = fullfile('data', 'evaluation_results'); end
    if ~isfield(params, 'frameIndices'), params.frameIndices = [1, 50, 100]; end
    if ~isfield(params, 'skipAblation'), params.skipAblation = false; end
    if ~isfield(params, 'verbose'),      params.verbose = true; end

    outDir = params.outputDir;
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    v = params.verbose;
    if v, fprintf('========================================\n'); end
    if v, fprintf('  Evaluation Pipeline Started\n'); end
    if v, fprintf('  Output Directory: %s\n', outDir); end
    if v, fprintf('========================================\n\n'); end

    evalResults = struct();

    % ================================================================
    % Stage 1: Ablation Study
    % ================================================================
    if ~params.skipAblation
        if v, fprintf('[Stage 1/5] Running ablation study...\n'); end

        ablationParams = struct();
        % Use the first available input video if specified
        ablationParams.saveResults = true;
        ablationParams.resultsDir  = fullfile(outDir, 'ablation');
        ablationParams.verbose     = v;

        if isfield(params, 'ablationMatrix') && ~isempty(params.ablationMatrix)
            ablationParams.ablationMatrix = params.ablationMatrix;
        end

        % Call ablation study (requires input video)
        if ~isfield(params, 'inputVideo') || isempty(params.inputVideo)
            warning('inputVideo not specified, skipping ablation study');
            evalResults.ablationTable = [];
        else
            ablationParams.inputVideo = params.inputVideo;
            ablationTable = run_ablation_study(params.inputVideo, ablationParams);
            evalResults.ablationTable = ablationTable;
            if v, fprintf('[Stage 1/5] Ablation study completed\n\n'); end
        end
    else
        if v, fprintf('[Stage 1/5] Skipping ablation study\n\n'); end
    end

    % ================================================================
    % Stage 2: Module Time Pie Chart
    % ================================================================
    if v, fprintf('[Stage 2/5] Generating module time pie charts...\n'); end
    if isfield(evalResults, 'ablationTable') && ~isempty(evalResults.ablationTable)
        ablationTable = evalResults.ablationTable;

        % Generate pie chart for each experiment
        nExp = height(ablationTable);
        pieFigs = cell(nExp, 1);
        for e = 1:nExp
            pieParams = struct();
            pieParams.savePath = fullfile(outDir, 'ablation', ...
                sprintf('pie_%s.png', ablationTable.Experiment{e}));
            pieParams.title = 'Module Time Distribution';
            pieParams.experimentIdx = e;

            try
                pieFigs{e} = visualize_module_pie(ablationTable, pieParams);
            catch ME
                warning('Pie chart generation failed for experiment %d: %s', e, ME.message);
            end
        end
        evalResults.pieFigures = pieFigs;
        if v, fprintf('[Stage 2/5] Pie chart generation completed (%d charts)\n\n', nExp); end
    else
        if v, fprintf('[Stage 2/5] No ablation data, skipping pie charts\n\n'); end
    end

    % ================================================================
    % Stage 3: Ablation Bar Chart
    % ================================================================
    if v, fprintf('[Stage 3/5] Generating ablation bar chart...\n'); end
    if isfield(evalResults, 'ablationTable') && ~isempty(evalResults.ablationTable)
        barParams = struct();
        barParams.savePath = fullfile(outDir, 'ablation', 'ablation_bars.png');
        barParams.title    = 'Ablation Study Performance Comparison';
        barParams.sortBy   = 'PSNR';

        try
            barFig = visualize_ablation_bars(evalResults.ablationTable, barParams);
            evalResults.barFigure = barFig;
            if v, fprintf('[Stage 3/5] Bar chart generation completed\n\n'); end
        catch ME
            warning('Bar chart generation failed: %s', ME.message);
        end
    else
        if v, fprintf('[Stage 3/5] No ablation data, skipping bar chart\n\n'); end
    end

    % ================================================================
    % Stage 4: Frame Comparison Visualization
    % ================================================================
    if v, fprintf('[Stage 4/5] Generating frame comparison visualization...\n'); end
    if ~isfield(params, 'inputVideo') || isempty(params.inputVideo)
        if v, fprintf('[Stage 4/5] inputVideo not specified, skipping frame comparison\n\n'); end
    else
        try
            % Find corresponding stabilized output
            [vidDir, vidName, ~] = fileparts(params.inputVideo);
            stabilizedPath = fullfile(outDir, 'ablation', ...
                sprintf('%s_baseline_stabilized.mp4', vidName));

            if exist(stabilizedPath, 'file')
                rawFrames = load_video(params.inputVideo);
                stabFrames = load_video(stabilizedPath);

                frameParams = struct();
                frameParams.savePath = fullfile(outDir, 'frame_comparison.png');
                frameParams.title    = sprintf('Frame Comparison: %s', vidName);

                figComp = visualize_frame_comparison(rawFrames, stabFrames, ...
                    params.frameIndices, frameParams);
                evalResults.frameComparisonFig = figComp;
                if v, fprintf('[Stage 4/5] Frame comparison completed\n\n'); end
            else
                if v, fprintf('[Stage 4/5] Stabilized video %s does not exist, skipping frame comparison\n\n', stabilizedPath); end
            end
        catch ME
            warning('Frame comparison generation failed: %s', ME.message);
        end
    end

    % ================================================================
    % Stage 5: Failure Case Analysis
    % ================================================================
    if v, fprintf('[Stage 5/5] Running failure case analysis...\n'); end
    diagDir = fullfile(outDir, 'ablation');
    if exist(diagDir, 'dir')
        diagFiles = dir(fullfile(diagDir, '*_diag.mat'));
        if ~isempty(diagFiles)
            % Analyze the first diagnostic file
            diagPath = fullfile(diagDir, diagFiles(1).name);
            failParams = struct();
            failParams.analysisPath = fullfile(outDir, 'failure_analysis.mat');
            failParams.verbose = v;

            try
                failReport = analyze_failure_cases(diagPath, failParams);
                evalResults.failureReport = failReport;
                if v, fprintf('[Stage 5/5] Failure case analysis completed\n\n'); end
            catch ME
                warning('Failure case analysis failed: %s', ME.message);
            end
        else
            if v, fprintf('[Stage 5/5] No diagnostic files, skipping failure case analysis\n\n'); end
        end
    else
        if v, fprintf('[Stage 5/5] Diagnostic directory %s does not exist, skipping failure case analysis\n\n', diagDir); end
    end

    % ================================================================
    % Generate Markdown Report
    % ================================================================
    if v, fprintf('Generating evaluation report...\n'); end
    reportPath = fullfile(outDir, 'evaluation_report.md');
    generateReport(evalResults, reportPath, params, v);

    if v, fprintf('\n========================================\n'); end
    if v, fprintf('  Evaluation complete! Report: %s\n', reportPath); end
    if v, fprintf('========================================\n'); end
end

%% ---- Helper: Generate Markdown Report ----
function generateReport(evalResults, reportPath, params, verbose)
    fid = fopen(reportPath, 'w');
    if fid == -1
        warning('Unable to create report file: %s', reportPath);
        return;
    end

    fprintf(fid, '# Video Stabilization Comprehensive Evaluation Report\n\n');
    fprintf(fid, 'Generated at: %s\n\n', datestr(now));

    if isfield(params, 'inputVideo')
        fprintf(fid, 'Input Video: `%s`\n\n', params.inputVideo);
    end

    % Ablation Experiment Results
    if isfield(evalResults, 'ablationTable') && ~isempty(evalResults.ablationTable)
        fprintf(fid, '## Ablation Experiment Results\n\n');
        fprintf(fid, '| Experiment | PSNR (dB) | SSIM | SR | MotionEst (ms) | Smoothing (ms) | Synthesis (ms) |\n');
        fprintf(fid, '|----------|-----------|------|-----|---------------|-----------|-------------|\n');

        tbl = evalResults.ablationTable;
        for r = 1:height(tbl)
            fprintf(fid, '| %s | %.2f | %.4f | %.2f | %.2f | %.2f | %.2f |\n', ...
                tbl.Experiment{r}, ...
                tbl.PSNR_dB(r), tbl.SSIM(r), tbl.SR(r), ...
                tbl.MotionEst_ms(r), tbl.Smoothing_ms(r), tbl.Synthesis_ms(r));
        end
        fprintf(fid, '\n');

        % Chart references
        fprintf(fid, '![Ablation Bar Chart](ablation/ablation_bars.png)\n\n');
        fprintf(fid, '### Module Time Distribution\n\n');
        for e = 1:height(tbl)
            fprintf(fid, '- %s: ![Pie](ablation/pie_%s.png)\n', tbl.Experiment{e}, tbl.Experiment{e});
        end
        fprintf(fid, '\n');
    end

    % Failure Case Analysis
    if isfield(evalResults, 'failureReport')
        rpt = evalResults.failureReport;
        fprintf(fid, '## Failure Case Analysis\n\n');
        fprintf(fid, '```\n%s\n```\n\n', strrep(rpt.summary, '\n', newline));
    end

    % Frame Comparison
    if isfield(evalResults, 'frameComparisonFig')
        fprintf(fid, '## Frame Comparison Visualization\n\n');
        fprintf(fid, '![Frame Comparison](frame_comparison.png)\n\n');
    end

    fclose(fid);
    if verbose, fprintf('Markdown report saved: %s\n', reportPath); end
end

