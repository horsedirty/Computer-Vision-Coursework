% run_frame_synthesis.m —— 模块三主入口
% 编码规范：参见项目根目录 AGENTS.md
% 角色六负责实现
%
% 功能：串联 warp → 边界处理 → 去模糊的完整流程。
% 接收模块二输出的平滑变换矩阵和原始帧，逐帧输出稳定+清晰的视频帧。
%
% 流水线：
%   rawFrame ──▶ warp_frame ──▶ [条件] estimate_blur_kernel ──▶ wiener_deblur ──▶ stabilizedFrame
%
% 模块间数据契约：
%   - 输入 rawFrame (uint8 H×W×3) + T_smoothed (3×3) + T_raw (3×3)
%   - 输出 stabilizedFrame (uint8，与输入同尺寸或按裁剪后尺寸)
%   - 本模块不修改 T_smoothed / T_raw，只读取使用
%
% 参考论文：14_LightStab (CVPR 2026) —— 整体流水线架构
%          06_深度运动盲视频防抖 —— 全帧输出与边界处理
%          07_GoPro (CVPR 2017) —— 模糊核物理建模与去模糊评估
%          12_门控时空注意力 (CVPR 2021) —— 清晰度评估指标
%
% INPUT:
%   rawFrame        - 原始帧，uint8 H×W×3
%   T_smoothed      - 3×3，当前帧的平滑变换矩阵
%   T_raw           - 3×3，当前帧的原始变换矩阵（用于模糊核估计）
%   frameIndex      - 当前帧在序列中的位置
%   params          - 参数字典
%     .warp_params     - 传递给 warp_frame 的参数
%     .blur_params     - 传递给 estimate_blur_kernel 的参数
%     .deblur_params   - 传递给 wiener_deblur 的参数
%     .enable_deblur   - 是否启用来模糊，默认 true
%     .deblurThreshold - 拉普拉斯方差跳跃阈值：当 warp 后清晰度
%                       相对于 blur 前提升低于此比例时触发去模糊
%                       默认 0.95（warp 后清晰度 < 95% 原始值 → 去模糊）
%
% OUTPUT:
%   stabilizedFrame - uint8 H×W×3，最终的稳定去模糊帧
%   cropRect        - warp 中的裁剪区域 [x, y, w, h]
%   diagnostics     - struct，各步骤耗时与统计

function [stabilizedFrame, cropRect, diagnostics] = run_frame_synthesis(rawFrame, T_smoothed, T_raw, frameIndex, params)
    arguments
        rawFrame uint8
        T_smoothed (3,3) double
        T_raw (3,3) double
        frameIndex (1,1) double
        params struct = struct()
    end

    % 手动维度验证（支持灰度和彩色帧）
    assert(ismatrix(rawFrame) || ndims(rawFrame) == 3, ...
        'rawFrame 必须是 2D（灰度）或 3D（彩色）uint8 矩阵');

    t_total = tic;

    warp_params     = safeField(params, 'warp_params', struct());
    blur_params     = safeField(params, 'blur_params', struct());
    deblur_params   = safeField(params, 'deblur_params', struct());
    enable_deblur   = safeField(params, 'enable_deblur', true);
    deblurThreshold = safeField(params, 'deblurThreshold', 0.95);

    % ================================================================
    % 步骤 1: Warp（仿射变换 + 边界处理 + 裁剪）
    % 将原始帧按平滑后的变换矩阵 warp 到稳定位置
    % ================================================================
    t1 = tic;
    [warpedFrame, cropRect, warpDiag] = warp_frame(rawFrame, T_smoothed, warp_params);
    warpTime = toc(t1);

    % ================================================================
    % 步骤 2: 去模糊（条件执行）
    % 条件判断流程：
    %   1. enable_deblur 必须为 true
    %   2. 估计模糊核，如果 blurLen < minBlurLen → 无需去模糊
    %   3. wiener_deblur 内部评估清晰度，自适应跳过
    % ================================================================
    t2 = tic;
    deblurApplied = false;
    blurLen = 0;
    blurDiag = [];
    deblurDiag = [];

    if enable_deblur
        [psf, ~, blurLen, blurDiag] = estimate_blur_kernel(T_raw, T_smoothed, frameIndex, blur_params);

        needsDeblur = ~(isscalar(psf) && abs(psf - 1) < 1e-9);

        if needsDeblur
            % 检查 warp 后是否需要去模糊：
            % 如果 warp 后清晰度相比原始帧下降超过阈值比例，说明运动抖动
            % 在 warp 过程中引入了额外模糊（边界填充、插值等），需要去模糊补偿
            sharpnessRaw = estimate_sharpness(rawFrame);
            sharpnessWarped = estimate_sharpness(warpedFrame);
            sharpnessRatio = sharpnessWarped / max(sharpnessRaw, 1e-6);

            if sharpnessRatio < deblurThreshold
                [warpedFrame, deblurDiag] = wiener_deblur(warpedFrame, psf, deblur_params);
                deblurApplied = true;
            end
        end
    end
    deblurTime = toc(t2);

    stabilizedFrame = warpedFrame;
    totalTime = toc(t_total);

    % ================================================================
    % 汇总诊断
    % ================================================================
    diagnostics = struct(...
        'warp_time_ms',     warpTime * 1000, ...
        'deblur_time_ms',   deblurTime * 1000, ...
        'total_time_ms',    totalTime * 1000, ...
        'deblur_applied',   deblurApplied, ...
        'blurLen_pixels',   blurLen, ...
        'warp_details',     warpDiag, ...
        'blur_details',     blurDiag, ...
        'deblur_details',   deblurDiag);
end


%% ====== 局部辅助函数 ======

function sharpness = estimate_sharpness(frame)
    % 计算拉普拉斯方差作为无参考清晰度指标
    % 参考：Pech-Pacheco et al. (2000)，12_门控时空注意力
    if size(frame, 3) == 3
        grayFrame = rgb2gray(frame);
    else
        grayFrame = frame;
    end
    laplacianKernel = fspecial('laplacian', 0.2);
    lapResponse = imfilter(double(grayFrame), laplacianKernel, 'symmetric', 'same', 'conv');
    sharpness = var(lapResponse(:));
end


function val = safeField(s, fieldname, default)
    if isfield(s, fieldname)
        val = s.(fieldname);
    else
        val = default;
    end
end


%% ====== 自测 ======
% 使用合成数据验证完整流水线：
% raw = imread('peppers.png');
% T_raw_test = eye(3); T_raw_test(1,3) = 4; T_raw_test(2,3) = 3;
% T_smoothed_test = eye(3);
% warp_params = struct('fillMethod', 'symmetric', 'cropEnabled', true);
% blur_params = struct('kernelLength', 31, 'motionScale', 1.0);
% deblur_params = struct('method', 'wiener', 'nsr', 0.01);
% all_params = struct('warp_params', warp_params, 'blur_params', blur_params, ...
%     'deblur_params', deblur_params, 'enable_deblur', true);
% [stab, crop, diag] = run_frame_synthesis(raw, T_smoothed_test, T_raw_test, 1, all_params);
% fprintf('Warp: %.1fms | Deblur: %s | Total: %.1fms\n', ...
%     diag.warp_time_ms, ternary(diag.deblur_applied, '✓', '-'), diag.total_time_ms);
