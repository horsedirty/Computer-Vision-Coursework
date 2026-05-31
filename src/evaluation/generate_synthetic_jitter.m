%% generate_synthetic_jitter.m —— 合成抖动数据集生成脚本
% 编码规范：参见项目根目录 AGENTS.md
% 
% 功能：针对输入的平稳视频，注入可控的仿射抖动参数（平移与旋转），
% 生成模拟各种场景的测试视频，并保存真实的变换矩阵作为 Ground Truth。
%
% INPUT:
%   inputFile  - 原始平稳视频路径
%   outputFile - 带有抖动的输出视频路径
%   params     - 参数字典
%     .jitterType - 'static_standing' | 'handheld_walking' | 'quick_panning' | 'bumpy_riding'
%     .addBlur    - 是否加入基于位移的运动模糊 (默认 false)
%
% OUTPUT:
%   T_groundtruth - 3x3xN 的真实变换矩阵序列，同时会被保存为 .mat 文件

function T_groundtruth = generate_synthetic_jitter(inputFile, outputFile, params)
    arguments
        inputFile (1,:) char
        outputFile (1,:) char
        params struct = struct()
    end
    
    % 设置默认参数
    if ~isfield(params, 'jitterType'), params.jitterType = 'handheld_walking'; end
    if ~isfield(params, 'addBlur'), params.addBlur = false; end
    
    % 使用现有工具加载视频信息
    v = VideoReader(inputFile);
    N = v.NumFrames;
    H = v.Height;
    W = v.Width;
    fps = v.FrameRate;
    
    fprintf('========== 合成抖动数据集生成 ==========\n');
    fprintf('模式: %s\n', params.jitterType);
    fprintf('总帧数: %d\n', N);
    
    % 1. 生成抖动参数 (Tx, Ty, Theta)
    Tx = zeros(1, N);
    Ty = zeros(1, N);
    Theta = zeros(1, N); % 弧度
    
    t = (0:N-1) / fps; % 时间轴(秒)
    
    switch params.jitterType
        case 'static_standing'
            % 低频、低振幅的随机漫步
            Tx = cumsum(randn(1, N)) * 0.5;
            Ty = cumsum(randn(1, N)) * 0.5;
            Theta = cumsum(randn(1, N)) * 0.001;
            
        case 'handheld_walking'
            % 垂直正弦波(模拟脚步) + 水平低频晃动 + 高斯噪声
            stepFreq = 1.8; % 1.8 步/秒
            Ty = 15 * sin(2 * pi * stepFreq * t) + 2 * randn(1, N);
            Tx = 5 * sin(2 * pi * (stepFreq/2) * t) + 2 * randn(1, N);
            Theta = 0.02 * sin(2 * pi * (stepFreq/2) * t) + 0.005 * randn(1, N);
            
        case 'quick_panning'
            % 中间某段大范围平移
            startPan = floor(N * 0.3);
            endPan = floor(N * 0.6);
            panSpeedX = 10;
            Tx(startPan:endPan) = (1:(endPan-startPan+1)) * panSpeedX;
            Tx(endPan+1:end) = Tx(endPan);
            Tx = Tx + 3 * randn(1, N); % 叠加少许手抖
            Ty = 3 * randn(1, N);
            Theta = 0.005 * randn(1, N);
            
        case 'bumpy_riding'
            % 高频高振幅噪声
            Tx = 20 * randn(1, N);
            Ty = 20 * randn(1, N);
            Theta = 0.05 * randn(1, N);
            % 用滑动平均稍微平滑一下，避免太过不连续
            Tx = smoothdata(Tx, 'gaussian', 3);
            Ty = smoothdata(Ty, 'gaussian', 3);
            
        otherwise
            error('未知的抖动类型: %s', params.jitterType);
    end
    
    % 将参数平滑过渡到0起始点
    Tx = Tx - Tx(1);
    Ty = Ty - Ty(1);
    Theta = Theta - Theta(1);
    
    % 2. 构建 T 矩阵序列
    T_groundtruth = repmat(eye(3), [1, 1, N]);
    for i = 1:N
        c = cos(Theta(i));
        s = sin(Theta(i));
        % 仿射变换矩阵构造（MATLAB 中仿射矩阵的平移在最后一行）
        T_groundtruth(:,:,i) = [
            c,  s, 0;
           -s,  c, 0;
            Tx(i), Ty(i), 1
        ];
    end
    
    % 保存 groundtruth 数据
    [outPath, outName, ~] = fileparts(outputFile);
    gtFile = fullfile(outPath, sprintf('%s_groundtruth.mat', outName));
    save(gtFile, 'T_groundtruth', 'params', 'Tx', 'Ty', 'Theta');
    fprintf('真实抖动参数已保存至: %s\n', gtFile);
    
    % 3. 逐帧渲染视频
    vw = VideoWriter(outputFile, 'MPEG-4');
    vw.FrameRate = fps;
    open(vw);
    
    v.CurrentTime = 0; % 重置读取位置
    
    % 中心点，用于旋转
    center = [W/2, H/2];
    
    hWait = waitbar(0, '正在生成抖动视频...');
    for i = 1:N
        if ~hasFrame(v)
            break;
        end
        frame = readFrame(v);
        
        % 取出对应的 T（MATLAB imwarp 使用的形式）
        % 为了以图像中心为轴旋转，我们需要：平移到原点 -> 旋转 -> 平移回中心 -> 施加Tx,Ty
        
        c = cos(Theta(i));
        s = sin(Theta(i));
        
        % 构造以中心旋转的仿射矩阵
        shiftToOrigin = [1 0 0; 0 1 0; -center(1) -center(2) 1];
        rotMat = [c s 0; -s c 0; 0 0 1];
        shiftBack = [1 0 0; 0 1 0; center(1) center(2) 1];
        translateMat = [1 0 0; 0 1 0; Tx(i) Ty(i) 1];
        
        T_final = shiftToOrigin * rotMat * shiftBack * translateMat;
        tform = affine2d(T_final);
        
        % 对图像进行仿射变换
        % 'FillValues' 用于边界黑色填充
        [warpedFrame, ~] = imwarp(frame, tform, 'OutputView', imref2d(size(frame)), ...
                                  'FillValues', 0);
        
        % （可选）简单模拟运动模糊
        if params.addBlur && i > 1
            dx = Tx(i) - Tx(i-1);
            dy = Ty(i) - Ty(i-1);
            len = sqrt(dx^2 + dy^2);
            if len > 2
                angle = atan2d(-dy, dx); % atan2d 角度
                hBlur = fspecial('motion', min(len, 20), angle); % 限制最大模糊长度
                warpedFrame = imfilter(warpedFrame, hBlur, 'replicate');
            end
        end
        
        writeVideo(vw, warpedFrame);
        waitbar(i/N, hWait, sprintf('处理进度: %d/%d', i, N));
    end
    
    close(hWait);
    close(vw);
    fprintf('抖动视频已保存至: %s\n', outputFile);
    fprintf('生成完毕！\n');
end

%% 自测
% if false
%     inputFile = 'data/test_videos/test1.mp4'; % 假设有个平稳视频
%     outputFile = 'data/test_videos/test1_bumpy.mp4';
%     params.jitterType = 'bumpy_riding';
%     params.addBlur = true;
%     generate_synthetic_jitter(inputFile, outputFile, params);
% end
