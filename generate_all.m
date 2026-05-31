% 快速生成脚本
addpath(genpath('src'));

inputFile = 'src/data/origin.mp4';
outDir = 'data/test_videos/';

jitters = {'static_standing', 'handheld_walking', 'quick_panning', 'bumpy_riding'};

for i = 1:length(jitters)
    jType = jitters{i};
    outputFile = fullfile(outDir, ['synth_', jType, '.mp4']);
    params = struct();
    params.jitterType = jType;
    params.addBlur = true; % 添加运动模糊
    fprintf('正在生成: %s\n', jType);
    generate_synthetic_jitter(inputFile, outputFile, params);
end

fprintf('所有视频生成完毕。\n');
