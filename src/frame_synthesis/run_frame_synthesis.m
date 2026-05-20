%% run_frame_synthesis.m —— 模块三主入口
% 编码规范：参见项目根目录 AGENTS.md
% 角色六负责实现
%
% 功能：串联 warp → 边界处理 → 去模糊的完整流程。
% 接收模块二输出的平滑变换矩阵和原始帧，逐帧输出稳定+清晰的视频帧。
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
%     .deblur_threshold - 拉普拉斯方差提升阈值：低于此值跳过去模糊，默认 0.05
%
% OUTPUT:
%   stabilizedFrame - uint8，最终的稳定去模糊帧
%   cropRect        - warp 中的裁剪区域
%   diagnostics     - struct，各步骤耗时

function [stabilizedFrame, cropRect, diagnostics] = run_frame_synthesis(rawFrame, T_smoothed, T_raw, frameIndex, params)
    arguments
        rawFrame (:,:,:) uint8
        T_smoothed (3,3) double
        T_raw (3,3) double
        frameIndex (1,1) double
        params struct = struct()
    end

    t_total = tic;

    warp_params   = safeField(params, 'warp_params', struct());
    blur_params   = safeField(params, 'blur_params', struct());
    deblur_params = safeField(params, 'deblur_params', struct());
    enable_deblur = safeField(params, 'enable_deblur', true);
    deblur_thresh = safeField(params, 'deblur_threshold', 0.05);

    % ================================================================
    % 步骤 1: Warp（仿射变换 + 边界处理 + 裁剪）
    % ================================================================
    t1 = tic;
    [warpedFrame, cropRect, warpDiag] = warp_frame(rawFrame, T_smoothed, warp_params);
    warp_time = toc(t1);

    % ================================================================
    % 步骤 2: 去模糊（条件执行）
    % ================================================================
    t2 = tic;
    deblurApplied = false;

    if enable_deblur
        % 模糊度预估
        % TODO: sharpness_raw = estimate_sharpness(rawFrame);
        % sharpness_warped = estimate_sharpness(warpedFrame);
        % 如果 warp 后清晰度已经提升超过阈值，跳过
        % if (sharpness_warped / max(sharpness_raw, 1e-6)) < (1 + deblur_threshold)
        %     enable_deblur = false;
        % end

        if enable_deblur
            % 估计模糊核（从 warp 前后差异）
            [psf, ~, ~, blurDiag] = estimate_blur_kernel(T_raw, T_smoothed, frameIndex, blur_params);

            % 维纳去卷积
            [warpedFrame, deblurDiag] = wiener_deblur(warpedFrame, psf, deblur_params);
            deblurApplied = true;
        end
    end
    deblur_time = toc(t2);

    stabilizedFrame = warpedFrame;
    total_time = toc(t_total);

    % ================================================================
    % 汇总诊断
    % ================================================================
    diagnostics = struct(...
        'warp_time_ms',       warp_time * 1000, ...
        'deblur_time_ms',     deblur_time * 1000, ...
        'total_time_ms',      total_time * 1000, ...
        'deblur_applied',     deblurApplied, ...
        'warp_details',       warpDiag);
end


function val = safeField(s, fieldname, default)
    if isfield(s, fieldname)
        val = s.(fieldname);
    else
        val = default;
    end
end
