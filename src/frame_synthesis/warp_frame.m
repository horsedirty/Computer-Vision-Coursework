% warp_frame.m —— 仿射 Warp 帧合成
% 编码规范：参见项目根目录 AGENTS.md
% 角色六负责实现
%
% 功能：使用平滑后的全局变换矩阵对原始帧做几何变换（warp），
% 生成稳定帧。采用像素级有效区域检测，精确裁除黑边。
%
% 策略：
%   1. SameAsInput 出口视图 → 保证输出尺寸与输入一致
%   2. 从像素值检测有效（非黑）区域 → 不受变换类型影响
%   3. 裁剪有效区域 + 缩放到目标尺寸 → 无黑边输出
%
% 参考论文：06_深度运动盲视频防抖（全帧输出策略）
%          11_多网格warping在线视频防抖（自适应裁剪思路）
%
% INPUT:
%   rawFrame    - 原始帧，uint8 H×W×3 或 H×W
%   T           - 3×3 变换矩阵（平滑后的）
%   params      - 参数字典
%     .cropEnabled    - 是否检测并裁除黑边，默认 true
%     .outputSize     - 输出尺寸 [H_out, W_out]，默认 []（= 原始尺寸）
%     .maxCropRatio   - 最小保留面积比例，默认 0.7
%
% OUTPUT:
%   warpedFrame - uint8，warp 后的稳定帧（无黑边）
%   cropRect    - [x, y, w, h]，有效区域在原输出中的位置
%   diagnostics - struct

function [warpedFrame, cropRect, diagnostics] = warp_frame(rawFrame, T, params)
    arguments
        rawFrame (:,:,:) uint8
        T (3,3) double
        params struct = struct()
    end

    cropEnabled  = safeField(params, 'cropEnabled', true);
    outputSize   = safeField(params, 'outputSize', []);
    maxCropRatio = safeField(params, 'maxCropRatio', 0.7);

    [H, W, ~] = size(rawFrame);
    if isempty(outputSize)
        outputSize = [H, W];
    end
    t_start = tic;

    % ================================================================
    % 步骤 1: 创建几何变换对象
    % ================================================================
    isAffine = abs(T(3,1)) < 1e-9 && abs(T(3,2)) < 1e-9 && abs(T(3,3) - 1) < 1e-9;

    if isAffine
        tform = affinetform2d(T(1:2, :));
    else
        tform = projtform2d(T);
    end

    % ================================================================
    % 步骤 2: 执行 Warp（SameAsInput 视图）
    % SameAsInput 保证输出尺寸与输入一致，适合流水线逐帧处理
    % 变换超出边界的像素 → FillValues=0（黑色）
    % ================================================================
    outputView = affineOutputView([H, W], tform, 'BoundsStyle', 'SameAsInput');
    warpedRaw = imwarp(rawFrame, tform, 'OutputView', outputView, 'FillValues', 0);

    % ================================================================
    % 步骤 3: 检测有效区域并裁剪
    % 从像素值出发检测非黑区：不依赖变换类型的假设
    % 在灰度图上做二值化 → 找包含全部有效像素的最小外接矩形
    % ================================================================
    [validRect, validPixels] = find_valid_region(warpedRaw);

    if cropEnabled
        validW = validRect(3);
        validH = validRect(4);
        originalPixels = W * H;

        minPixels = originalPixels * maxCropRatio;
        if validPixels < minPixels
            scale = sqrt(minPixels / validPixels);
            centerX = validRect(1) + validRect(3) / 2;
            centerY = validRect(2) + validRect(4) / 2;
            newW = validW * scale;
            newH = validH * scale;
            validRect = [max(1, round(centerX - newW/2)), ...
                         max(1, round(centerY - newH/2)), ...
                         min(W, round(newW)), ...
                         min(H, round(newH))];
        end

        cropRect = validRect;
        warpedFrame = imcrop(warpedRaw, cropRect);
    else
        warpedFrame = warpedRaw;
        cropRect = [1, 1, W, H];
    end

    % ================================================================
    % 步骤 4: 缩放到目标输出尺寸
    % ================================================================
    if size(warpedFrame, 1) ~= outputSize(1) || size(warpedFrame, 2) ~= outputSize(2)
        warpedFrame = imresize(warpedFrame, outputSize);
    end

    elapsed = toc(t_start);

    [Hout, Wout, ~] = size(warpedFrame);
    validPixelCount = validRect(3) * validRect(4);
    pixelRetention = validPixelCount / (W * H);

    diagnostics = struct(...
        'cropEnabled', cropEnabled, ...
        'cropRect', cropRect, ...
        'output_size', [Hout, Wout], ...
        'pixel_retention', pixelRetention, ...
        'valid_pixels', validPixelCount, ...
        'max_shift_pixels', max(abs(T(1,3)), abs(T(2,3))), ...
        'is_affine', isAffine, ...
        'warp_time_ms', elapsed * 1000);
end


%% ====== 局部辅助函数 ======

function [rect, pixelCount] = find_valid_region(img)
    % 从像素值检测有效（非黑）区域的最小外接矩形
    % 在灰度图上做：亮度 < 5 → 黑边，亮度 ≥ 5 → 有效内容
    if size(img, 3) == 3
        gray = rgb2gray(img);
    else
        gray = img;
    end

    nonBlack = gray > 5;

    [rows, cols] = find(nonBlack);

    if isempty(rows)
        rect = [1, 1, size(img, 2), size(img, 1)];
        pixelCount = size(img, 1) * size(img, 2);
        return;
    end

    colMin = min(cols);
    colMax = max(cols);
    rowMin = min(rows);
    rowMax = max(rows);

    rect = [colMin, rowMin, colMax - colMin + 1, rowMax - rowMin + 1];
    pixelCount = nnz(nonBlack);
end


function val = safeField(s, fieldname, default)
    if isfield(s, fieldname)
        val = s.(fieldname);
    else
        val = default;
    end
end


%% ====== 自测 ======
% 使用一个简单平移变换验证 warp 管线：
% raw = imread('peppers.png');
% T_test = eye(3); T_test(1,3) = 15; T_test(2,3) = -10;
% params = struct('cropEnabled', true);
% [warped, cropRect, diag] = warp_frame(raw, T_test, params);
% imshowpair(raw, warped, 'montage');
% fprintf('像素保留率: %.2f%%\n', diag.pixel_retention * 100);
