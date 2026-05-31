function [T_sequence, diagnostics] = vl_motion_estimation(videoObj)
    % VL_MOTION_ESTIMATION 基于 VLFeat 提取 SIFT 特征进行运动估计
    % 
    % INPUT:
    %   videoObj - VideoReader 对象
    % OUTPUT:
    %   T_sequence - 3x3xN 的双精度数组，记录每帧到前一帧的仿射变换
    %   diagnostics - 包含耗时和统计信息的结构体
    
    numFrames = videoObj.NumFrames;
    height = videoObj.Height;
    width = videoObj.Width;
    
    T_sequence = zeros(3, 3, numFrames);
    T_sequence(:,:,1) = eye(3);
    
    total_time_ms = 0;
    
    videoObj.CurrentTime = 0;
    if hasFrame(videoObj)
        prevFrame = readFrame(videoObj);
        prevGray = single(rgb2gray(prevFrame));
        % VLFeat 要求 single 类型，取值 0-255（不归一化到 0-1）
        tic;
        [prev_f, prev_d] = vl_sift(prevGray);
        total_time_ms = total_time_ms + toc * 1000;
    end
    
    for i = 2:numFrames
        if ~hasFrame(videoObj), break; end
        currFrame = readFrame(videoObj);
        currGray = single(rgb2gray(currFrame));
        
        tic;
        [curr_f, curr_d] = vl_sift(currGray);
        
        % 匹配
        [matches, scores] = vl_ubcmatch(prev_d, curr_d, 1.5);
        
        % 过滤和估计变换矩阵
        numMatches = size(matches, 2);
        if numMatches >= 3
            matchedPrev = prev_f(1:2, matches(1, :))';
            matchedCurr = curr_f(1:2, matches(2, :))';
            
            try
                % 暂时关闭烦人的 RANSAC 警告
                warnState = warning('off', 'vision:ransac:maxTrialsReached');
                warning('off', 'vision:estimateGeometricTransform2D:notEnoughInliers');
                % RANSAC 估计仿射变换 (curr -> prev)
                tform = estimateGeometricTransform2D(matchedCurr, matchedPrev, 'affine', 'MaxDistance', 1.5);
                T = tform.T;
                warning(warnState);
            catch
                warning('帧 %d: RANSAC 估计失败，回退为单位矩阵', i);
                T = eye(3);
            end
        else
            warning('帧 %d: 特征匹配数过少 (%d)，回退为单位矩阵', i, numMatches);
            T = eye(3);
        end
        
        T_sequence(:,:,i) = T;
        
        prev_f = curr_f;
        prev_d = curr_d;
        
        total_time_ms = total_time_ms + toc * 1000;
    end
    
    diagnostics.total_time_ms = total_time_ms;
    diagnostics.avg_time_per_frame_ms = total_time_ms / max(1, numFrames - 1);
end
