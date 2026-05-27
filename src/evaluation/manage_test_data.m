%% manage_test_data.m —— 测试素材管理脚本
% 编码规范：参见项目根目录 AGENTS.md
% 角色八负责实现
%
% 功能：扫描 data/test_videos/ 目录，读取每个视频的元数据，
% 自动生成或更新 index.csv 索引文件。
%
% INPUT:
%   params - 参数字典
%     .videoDir   - 测试视频目录，默认 'data/test_videos/'
%     .indexFile  - 索引文件路径，默认 'data/test_videos/index.csv'
%     .rebuild    - 是否重建（忽略已有记录），默认 false
%
% OUTPUT:
%   indexTable  - table，包含所有视频的元数据
%   updated     - 更新数量

function [indexTable, updated] = manage_test_data(params)
    arguments
        params struct = struct()
    end

    if ~isfield(params, 'videoDir'),  params.videoDir = fullfile('data', 'test_videos'); end
    if ~isfield(params, 'indexFile'), params.indexFile = fullfile(params.videoDir, 'index.csv'); end
    if ~isfield(params, 'rebuild'),   params.rebuild = false; end

    fprintf('========== 测试素材管理 ==========
');
    fprintf('视频目录: %s
', params.videoDir);
    fprintf('索引文件: %s
', params.indexFile);

    % === 第一步：扫描视频文件 ===
    videoExts = {'*.mp4', '*.avi', '*.mov', '*.mkv', '*.wmv'};
    videoFiles = {};
    for e = 1:numel(videoExts)
        files = dir(fullfile(params.videoDir, videoExts{e}));
        for f = 1:numel(files)
            if ~startsWith(files(f).name, '.')
                videoFiles{end+1, 1} = fullfile(params.videoDir, files(f).name);
            end
        end
    end

    if isempty(videoFiles)
        warning('未找到视频文件: %s', params.videoDir);
        indexTable = table();
        updated = 0;
        return;
    end

    fprintf('找到 %d 个视频文件

', numel(videoFiles));

    % === 第二步：加载已有索引 ===
    if exist(params.indexFile, 'file') && ~params.rebuild
        try
            existingTable = readtable(params.indexFile, 'Delimiter', ',');
            existingNames = existingTable.文件名;
            fprintf('已有索引包含 %d 条记录
', height(existingTable));
        catch
            existingNames = {};
        end
    else
        existingNames = {};
    end

    % === 第三步：逐视频提取元数据 ===
    nVideos = numel(videoFiles);
    allNames = cell(nVideos, 1);
    allWidths = zeros(nVideos, 1);
    allHeights = zeros(nVideos, 1);
    allFramerates = zeros(nVideos, 1);
    allFrames = zeros(nVideos, 1);
    allDurations = zeros(nVideos, 1);
    allSizes = zeros(nVideos, 1);
    updated = 0;

    for i = 1:nVideos
        [~, name, ext] = fileparts(videoFiles{i});
        fileName = [name ext];
        allNames{i} = fileName;

        % 获取文件大小 (KB)
        fileInfo = dir(videoFiles{i});
        allSizes(i) = round(fileInfo.bytes / 1024);

        % 如果已有记录且非重建模式，跳过
        if ismember(fileName, existingNames) && ~params.rebuild
            fprintf('  [跳过] %s（已有记录）
', fileName);
            continue;
        end

        % 使用 load_video 获取元数据
        try
            [~, metadata] = load_video(videoFiles{i}, struct('maxFrames', 1));
            allWidths(i) = metadata.Width;
            allHeights(i) = metadata.Height;
            allFramerates(i) = metadata.FrameRate;

            % 获取总帧数（快速方式：使用 VideoReader）
            v = VideoReader(videoFiles{i});
            allFrames(i) = v.NumFrames;
            allDurations(i) = v.Duration;

            fprintf('  [更新] %s: %d×%d, %.1f fps, %d 帧, %.1f s, %d KB
', ...
                fileName, metadata.Width, metadata.Height, ...
                metadata.FrameRate, v.NumFrames, v.Duration, allSizes(i));
            updated = updated + 1;
        catch ME
            fprintf('  [错误] %s: %s
', fileName, ME.message);
            allWidths(i) = NaN;
            allHeights(i) = NaN;
            allFramerates(i) = NaN;
            allFrames(i) = NaN;
            allDurations(i) = NaN;
            allSizes(i) = NaN;
        end
    end

    % === 第四步：构建表格并保存 ===
    % 保留用户可能手动填写的场景描述列
    sceneTypes = repmat({''}, nVideos, 1);
    lightConditions = repmat({''}, nVideos, 1);
    motionFeatures = repmat({''}, nVideos, 1);
    notes = repmat({''}, nVideos, 1);

    % 如果已有索引且非重建，保留场景描述
    if exist(params.indexFile, 'file') && ~params.rebuild
        try
            for i = 1:nVideos
                idx = find(strcmp(existingNames, allNames{i}), 1);
                if ~isempty(idx)
                    if ismember('场景类型', existingTable.Properties.VariableNames)
                        val = existingTable.场景类型{idx};
                        if ~isempty(val), sceneTypes{i} = val; end
                    end
                    if ismember('光照条件', existingTable.Properties.VariableNames)
                        val = existingTable.光照条件{idx};
                        if ~isempty(val), lightConditions{i} = val; end
                    end
                    if ismember('运动特征', existingTable.Properties.VariableNames)
                        val = existingTable.运动特征{idx};
                        if ~isempty(val), motionFeatures{i} = val; end
                    end
                    if ismember('备注', existingTable.Properties.VariableNames)
                        val = existingTable.备注{idx};
                        if ~isempty(val), notes{i} = val; end
                    end
                end
            end
        catch
        end
    end

    indexTable = table(allNames, allWidths, allHeights, allFramerates, ...
        allFrames, allDurations, allSizes, sceneTypes, lightConditions, ...
        motionFeatures, notes, ...
        'VariableNames', {'文件名', '宽度', '高度', '帧率', '总帧数', ...
                          '时长_秒', '大小_KB', '场景类型', '光照条件', ...
                          '运动特征', '备注'});

    if updated > 0
        writetable(indexTable, params.indexFile);
        fprintf('
索引已保存: %s（更新 %d 条）
', params.indexFile, updated);
    else
        fprintf('
无新记录（%d 个视频均已索引）
', nVideos);
    end

    % === 展示索引 ===
    disp(indexTable(:, {'文件名', '宽度', '高度', '帧率', '总帧数', '时长_秒', '大小_KB'}));
end
