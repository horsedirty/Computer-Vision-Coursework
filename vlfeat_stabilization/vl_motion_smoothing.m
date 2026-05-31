function [T_smoothed, diagnostics] = vl_motion_smoothing(T_sequence, windowSize)
    % VL_MOTION_SMOOTHING 对变换序列进行高斯窗口平滑
    % 累加 T_sequence 得到绝对轨迹，平滑后再求导得到平滑后的帧间变换。
    
    arguments
        T_sequence (3,3,:) double
        windowSize (1,1) double = 30
    end
    
    tic;
    numFrames = size(T_sequence, 3);
    
    % 计算累积变换 (绝对轨迹)
    T_cum = zeros(3, 3, numFrames);
    T_cum(:,:,1) = T_sequence(:,:,1);
    for i = 2:numFrames
        % MATLAB 的坐标是行向量 [x, y, 1]，复合变换为 T_curr_to_prev * T_prev_to_1
        T_cum(:,:,i) = T_sequence(:,:,i) * T_cum(:,:,i-1);
    end
    
    % 分解仿射参数
    params = zeros(numFrames, 6);
    for i = 1:numFrames
        T = T_cum(:,:,i);
        params(i,:) = [T(1,1), T(2,1), T(1,2), T(2,2), T(3,1), T(3,2)];
    end
    
    % 高斯平滑
    sigma = windowSize / 3;
    x = linspace(-windowSize/2, windowSize/2, windowSize);
    gaussFilter = exp(-x.^2 / (2 * sigma^2));
    gaussFilter = gaussFilter / sum(gaussFilter);
    
    smoothed_params = zeros(numFrames, 6);
    for j = 1:6
        smoothed_params(:,j) = filtfilt(gaussFilter, 1, params(:,j));
    end
    
    % 计算每一帧的绝对修正变换 T_correction
    T_smoothed = zeros(3, 3, numFrames);
    for i = 1:numFrames
        T_smooth = [smoothed_params(i,1), smoothed_params(i,3), 0; ...
                    smoothed_params(i,2), smoothed_params(i,4), 0; ...
                    smoothed_params(i,5), smoothed_params(i,6), 1];
                    
        % T_correction 是应用到原图上的变换： T_cum(i) * inv(T_smooth)
        T_correction = T_cum(:,:,i) / T_smooth;
        % 消除浮点数误差，强行保证仿射变换的最后一列为 [0; 0; 1]
        T_correction(:, 3) = [0; 0; 1];
        T_smoothed(:,:,i) = T_correction;
    end
    diagnostics.total_time_ms = toc * 1000;
    diagnostics.raw_Tx = params(:,5);
    diagnostics.raw_Ty = params(:,6);
    diagnostics.smoothed_Tx = smoothed_params(:,5);
    diagnostics.smoothed_Ty = smoothed_params(:,6);
end
