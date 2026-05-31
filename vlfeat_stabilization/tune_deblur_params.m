% TUNE_DEBLUR_PARAMS 独立脚本，用于快速调试去模糊算法的参数
%
% 这个脚本抽取视频中抖动最剧烈的一帧，模拟施加去模糊算法并展示对比图，
% 让您可以实现“秒级调参”，而不需要每次都等待漫长的全片运动估计过程。

% ====== 可调优的核心参数 ======

% 1. NSR (噪信比 Noise-to-Signal Ratio)
%    决定了维纳滤波对噪声和边缘断层的容忍度。
%    [偏小] (如 0.001 - 0.01): 图像极度锐利，但极容易产生全屏水波纹（振铃效应）。
%    [偏大] (如 0.05 - 0.2)  : 图像相对平滑，水波纹会显著减弱，但清晰度提升有限。
%    👉 去模糊没效果？优先调小此值（如 0.01 或 0.005）以增强锐化力度！
nsr = 0.2;

% 2. EXPOSURE_FRACTION (曝光时间占比)
%    决定了计算出的模糊核 (PSF) 的长度。
%    [偏大] (如 0.5 - 1.0): 假设快门时间长，模糊核变长，去模糊力度极大。
%    [偏小] (如 0.1 - 0.3): 假设快门时间短，模糊核短，去模糊非常轻微。
%    👉 您的脚本模拟了真实的动态模糊，因此应该放大此值（如 0.5 到 1.0），让核足够大！
exposure_fraction = 0.5; 

% 3. MAX_PSF_LEN (最大模糊核长度)
%    硬性限制 PSF 的最大像素尺寸。
%    👉 因为您的模拟抖动幅度很大（如 25-35 像素），必须放宽限制才能去掉大范围的模糊！
max_psf_len = 20;

% ==============================

clc; close all;

% 1. 加载视频
% 使用颠簸测试视频
videoPath = fullfile('..', 'data', 'test_videos', 'synth_bumpy_riding.mp4');
v = VideoReader(videoPath);

% 随意抽取一帧（比如第 15 帧，通常在剧烈运动中）
target_frame_idx = 50;
v.CurrentTime = (target_frame_idx - 1) / v.FrameRate;
frame = readFrame(v);

% 模拟一个非常大的运动向量 (假设该帧向右下剧烈抖动了 25 个像素)
% 在真实流水线中，这个向量是从 T_sequence 矩阵中读取的
dx = 25;
dy = 25;

disp('开始生成模糊核...');
% 2. 估算 PSF
motion_mag = sqrt(dx^2 + dy^2);

% --- 移除过度衰减 ---
% 既然视频自带了真实的模拟模糊，我们不需要去强行压低模糊核了！
% 完全信任您的基准参数，让去模糊火力全开！
adaptive_exp = exposure_fraction; 
adaptive_nsr = nsr;

motion_length = motion_mag * adaptive_exp;
motion_length = min(motion_length, max_psf_len);

if motion_length < 1.0
    disp('运动幅度过小，没有模糊');
    PSF = 1;
else
    theta = atan2d(-dy, dx);
    PSF = fspecial('motion', max(1, motion_length), theta);
end

disp('开始维纳滤波去卷积...');
% 3. 维纳滤波去卷积
tic;
img = im2double(frame);

% 边缘平滑 (Edge Tapering)，这是对抗边界水波纹的终极武器
if size(img, 3) == 3
    img(:,:,1) = edgetaper(img(:,:,1), PSF);
    img(:,:,2) = edgetaper(img(:,:,2), PSF);
    img(:,:,3) = edgetaper(img(:,:,3), PSF);
else
    img = edgetaper(img, PSF);
end

deblurred_img = zeros(size(img));
if size(img, 3) == 3
    for c = 1:3
        deblurred_img(:,:,c) = deconvwnr(img(:,:,c), PSF, adaptive_nsr);
    end
else
    deblurred_img = deconvwnr(img, PSF, adaptive_nsr);
end
deblurred_frame = im2uint8(deblurred_img);
t = toc;
fprintf('去模糊耗时: %.2f 秒\n', t);

% 4. 可视化对比
figure('Name', '去模糊参数秒级调试器', 'Position', [100, 100, 1200, 600]);

subplot(1,2,1);
imshow(frame);
title('原始帧 (存在运动模糊)');

subplot(1,2,2);
imshow(deblurred_frame);
title(sprintf('去模糊后 (耗时: %.2fs)\n基准Exp:%.2f -> 自适应:%.2f\n基准NSR:%.3f -> 自适应:%.3f\nMaxLen:%d', ...
      t, exposure_fraction, adaptive_exp, nsr, adaptive_nsr, max_psf_len));
