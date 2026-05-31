function run_vlfeat_stabilization()
    % RUN_VLFEAT_STABILIZATION 运行完整的 VLFeat 视频防抖测试流程
    
    % 1. 配置环境
    setup_vlfeat();
    
    % 2. 输入输出设置
    % 使用项目自带数据，这里假设有 data/test_videos/ 目录
    videoPath = fullfile('..', 'data', 'test_videos', 'synth_handheld_walking.mp4');
    if ~exist(videoPath, 'file')
        % 如果没有样本视频，尝试从项目根目录或者提供一个警告
        warning('未找到测试视频 %s, 请指定有效的视频路径。', videoPath);
        return;
    end
    
    outputPath = fullfile('..', 'data', 'results', 'vlfeat_handheld_stabilized.mp4');
    videoObj = VideoReader(videoPath);
    
    disp('=== 开始基于 VLFeat 的视频防抖流水线 ===');
    
    % 阶段 1: 运动估计
    disp('阶段一：运动估计...');
    [T_sequence, diag_est] = vl_motion_estimation(videoObj);
    fprintf('运动估计耗时: %.2f ms (每帧 %.2f ms)\n', diag_est.total_time_ms, diag_est.avg_time_per_frame_ms);
    
    % 阶段 2: 运动平滑
    disp('阶段二：运动平滑...');
    [T_smoothed, diag_smooth] = vl_motion_smoothing(T_sequence, 30);
    fprintf('运动平滑耗时: %.2f ms\n', diag_smooth.total_time_ms);
    
    % 阶段 3: 帧合成与去模糊
    disp('阶段三：帧合成与去模糊导出...');
    
    % 配置合成参数
    synth_params.enable_deblur = false;   % 原视频无光学运动模糊，关闭维纳去卷积，防止产生严重的振铃效应和额外模糊！
    synth_params.enable_sharpen = true;   % 开启 USM 锐化，补偿 imwarp 几何插值带来的平滑
    synth_params.exposure_fraction = 0.3; % 保留原参数以便未来真实视频使用
    synth_params.nsr = 0.05;              
    
    synth_params.crop_ratio = 0.05;       % 裁剪比例：裁掉边缘的 5% 以去除黑边
    synth_params.resize_to_original = false; % 不放大回原分辨率，避免强行放大导致的二次模糊
    
    diag_synth = vl_frame_synthesis(VideoReader(videoPath), T_smoothed, T_sequence, outputPath, synth_params);
    fprintf('帧合成耗时: %.2f ms\n', diag_synth.total_time_ms);
    
    disp('=== 视频防抖处理完成 ===');
    fprintf('输出路径: %s\n', outputPath);
    
    % 4. 算法评估与可视化
    [~, videoName, ~] = fileparts(videoPath);
    gtPath = fullfile('..', 'data', 'test_videos', [videoName, '_groundtruth.mat']);
    
    if exist(gtPath, 'file')
        disp('=== 算法评估 ===');
        gt = load(gtPath);
        fprintf('成功加载 Ground Truth 数据：%s\n', gtPath);
        
        numFrames = length(diag_smooth.raw_Tx);
        
        % 计算 RMSE (相对于 Ground Truth 的平移误差)
        % 取出前 numFrames 帧以防帧数不匹配
        maxFrames = min(numFrames, length(gt.Tx));
        gt_Tx = gt.Tx(1:maxFrames)';
        gt_Ty = gt.Ty(1:maxFrames)';
        
        sm_Tx = diag_smooth.smoothed_Tx(1:maxFrames);
        sm_Ty = diag_smooth.smoothed_Ty(1:maxFrames);
        
        rmse_x = sqrt(mean((sm_Tx - gt_Tx).^2));
        rmse_y = sqrt(mean((sm_Ty - gt_Ty).^2));
        rmse_total = sqrt(rmse_x^2 + rmse_y^2);
        
        fprintf('RMSE X轴: %.4f 像素\n', rmse_x);
        fprintf('RMSE Y轴: %.4f 像素\n', rmse_y);
        fprintf('总RMSE (平移误差): %.4f 像素\n', rmse_total);
        
        % 绘制轨迹对比图
        figHandle = figure('Name', '算法轨迹评估', 'NumberTitle', 'off');
        subplot(2,1,1);
        hold on;
        plot(1:maxFrames, diag_smooth.raw_Tx(1:maxFrames), 'r-', 'DisplayName', 'Raw Trajectory (Est)');
        plot(1:maxFrames, sm_Tx, 'b-', 'LineWidth', 1.5, 'DisplayName', 'Smoothed Trajectory (Est)');
        plot(1:maxFrames, gt_Tx, 'g--', 'LineWidth', 1.5, 'DisplayName', 'Ground Truth Trajectory');
        hold off;
        xlabel('Frame Number');
        ylabel('X Translation (pixels)');
        legend('Location', 'best');
        title('X 轴运动轨迹对比');
        grid on;
        
        subplot(2,1,2);
        hold on;
        plot(1:maxFrames, diag_smooth.raw_Ty(1:maxFrames), 'r-', 'DisplayName', 'Raw Trajectory (Est)');
        plot(1:maxFrames, sm_Ty, 'b-', 'LineWidth', 1.5, 'DisplayName', 'Smoothed Trajectory (Est)');
        plot(1:maxFrames, gt_Ty, 'g--', 'LineWidth', 1.5, 'DisplayName', 'Ground Truth Trajectory');
        hold off;
        xlabel('Frame Number');
        ylabel('Y Translation (pixels)');
        legend('Location', 'best');
        title('Y 轴运动轨迹对比');
        grid on;
        
        figPath = fullfile('..', 'data', 'results', [videoName, '_trajectory_eval.png']);
        saveas(figHandle, figPath);
        fprintf('轨迹对比图已保存至: %s\n', figPath);
    else
        disp('未找到对应的 Ground Truth 文件，跳过评估。');
    end
end
