function PSF = vl_estimate_blur_kernel(T_raw, exposure_fraction)
    % VL_ESTIMATE_BLUR_KERNEL 根据帧间抖动估计点扩散函数 (PSF)
    % 
    % INPUT:
    %   T_raw - 3x3 矩阵，当前帧到前一帧的原始仿射变换 (包含帧间抖动)
    %   exposure_fraction - 快门曝光时间占帧间隔的比例，范围 (0, 1]
    %
    % OUTPUT:
    %   PSF - 估算出的 2D 点扩散函数矩阵
    
    arguments
        T_raw (3,3) double
        exposure_fraction (1,1) double = 0.5
    end
    
    % 提取平移分量 (注意：如果含有强烈旋转也可在此扩展，但目前以平移为主)
    % T_raw 格式: [a b 0; c d 0; tx ty 1]
    dx = T_raw(3,1);
    dy = T_raw(3,2);
    
    % 在曝光时间内的有效运动距离 (像素)
    motion_length = sqrt(dx^2 + dy^2) * exposure_fraction;
    
    % 强制限制最大模糊核尺寸，防止因为剧烈抖动产生数十像素的模糊核，这会直接毁灭图像
    motion_length = min(motion_length, 15);
    
    % 如果运动幅度极小 (小于 1 个像素)，则认为没有模糊
    if motion_length < 1.0
        PSF = 1; % 无模糊时的脉冲核
        return;
    end
    
    % 计算运动方向 (度数)
    % y轴向下，所以向上位移需要反转
    theta = atan2d(-dy, dx);
    
    % 使用 Image Processing Toolbox 的 fspecial 函数生成运动模糊核
    % 注意：运动长度至少为 1
    PSF = fspecial('motion', max(1, motion_length), theta);
end
