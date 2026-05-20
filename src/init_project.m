%% init_project.m —— 项目初始化脚本
% 编码规范：参见项目根目录 AGENTS.md
% 所有成员首次使用时运行此脚本，自动添加 src/ 下所有子目录到 MATLAB 路径

function init_project()
    % 获取此脚本所在目录
    scriptDir = fileparts(mfilename('fullpath'));
    projectRoot = fileparts(scriptDir);  % 上一级是项目根目录

    % 添加所有 src 子目录
    addpath(fullfile(scriptDir, 'motion_estimation'));
    addpath(fullfile(scriptDir, 'motion_smoothing'));
    addpath(fullfile(scriptDir, 'frame_synthesis'));
    addpath(fullfile(scriptDir, 'evaluation'));
    addpath(fullfile(scriptDir, 'utils'));

    % 检查必要工具箱
    fprintf('=== 项目: 视频运动防抖与画面去模糊 ===\n');
    fprintf('项目根目录: %s\n', projectRoot);
    fprintf('MATLAB 版本: %s\n', version);

    % 检查工具箱可用性
    checkToolbox('Computer Vision Toolbox',     'VideoReader, detectSIFTFeatures, opticalFlowFarneback');
    checkToolbox('Image Processing Toolbox',    'imwarp, deconvwnr, fspecial');
    checkToolbox('Parallel Computing Toolbox',  'parfeval, parfor（可选，用于加速）');
    checkToolbox('Deep Learning Toolbox',       'importONNXNetwork（可选，用于轻量去模糊网络）');

    fprintf('\n路径已设置。运行 main_pipeline 开始处理。\n');
    fprintf('快速测试: cd(''%s''); main_pipeline(struct(''inputVideo'', ''your_video.mp4''));\n', scriptDir);
end

function checkToolbox(name, features)
    lic = license('test', mapToolbox(name));
    if lic
        fprintf('  [✓] %s (%s)\n', name, features);
    else
        fprintf('  [✗] %s — 未安装，相关功能不可用\n', name);
    end
end

function tb = mapToolbox(name)
    switch name
        case 'Computer Vision Toolbox'
            tb = 'Video_and_Image_Blockset';
        case 'Image Processing Toolbox'
            tb = 'Image_Toolbox';
        case 'Parallel Computing Toolbox'
            tb = 'Distrib_Computing_Toolbox';
        case 'Deep Learning Toolbox'
            tb = 'Neural_Network_Toolbox';
        otherwise
            tb = '';
    end
end
