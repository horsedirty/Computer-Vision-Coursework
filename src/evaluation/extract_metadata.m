%% extract_metadata.m —— 快速提取测试视频元数据
% 角色八负责，用于直接扫描 test_videos 并生成 index.csv

function extract_metadata()
    videoDir = fullfile('data', 'test_videos');
    indexFile = fullfile(videoDir, 'index.csv');
    
    % 扫描 mp4 文件
    d = dir(fullfile(videoDir, '*.mp4'));
    if isempty(d)
        error('未找到视频文件: %s', videoDir);
    end
    
    n = numel(d);
    names = cell(n, 1);
    widths = zeros(n, 1);
    heights = zeros(n, 1);
    framerates = zeros(n, 1);
    numFrames = zeros(n, 1);
    durations = zeros(n, 1);
    sizesKB = zeros(n, 1);
    
    for i = 1:n
        names{i} = d(i).name;
        fullPath = fullfile(videoDir, d(i).name);
        sizesKB(i) = round(d(i).bytes / 1024);
        
        try
            v = VideoReader(fullPath);
            widths(i) = v.Width;
            heights(i) = v.Height;
            framerates(i) = v.FrameRate;
            numFrames(i) = v.NumFrames;
            durations(i) = v.Duration;
            fprintf('[%d/%d] %s: %dx%d, %.2f fps, %d frames, %.2f s, %d KB\n', ...
                i, n, names{i}, widths(i), heights(i), ...
                framerates(i), numFrames(i), durations(i), sizesKB(i));
        catch ME
            fprintf('[%d/%d] %s: ERROR - %s\n', i, n, names{i}, ME.message);
            widths(i) = NaN; heights(i) = NaN;
            framerates(i) = NaN; numFrames(i) = NaN;
            durations(i) = NaN; sizesKB(i) = NaN;
        end
    end
    
    sceneType = repmat({''}, n, 1);
    lighting = repmat({''}, n, 1);
    motion = repmat({''}, n, 1);
    notes = repmat({''}, n, 1);
    
    T = table(names, widths, heights, framerates, numFrames, ...
        durations, sizesKB, sceneType, lighting, motion, notes, ...
        'VariableNames', {'文件名', '宽度', '高度', '帧率', '总帧数', ...
        '时长_秒', '大小_KB', '场景类型', '光照条件', '运动特征', '备注'});
    
    writetable(T, indexFile);
    fprintf('\n索引已保存: %s (%d 个视频)\n', indexFile, n);
    disp(T);
end
