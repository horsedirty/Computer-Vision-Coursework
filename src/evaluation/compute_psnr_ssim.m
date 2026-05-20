%% compute_psnr_ssim.m —— 评估指标：PSNR 和 SSIM
% 编码规范：参见项目根目录 AGENTS.md
% 角色八负责实现
%
% 功能：计算视频稳定前后的帧间质量指标。
% 帧间 PSNR 和 SSIM 越高 → 帧间差异越小 → 视频越稳定。
%
% INPUT:
%   frames      - H×W×3×N 或 cell array，视频帧序列
%   method      - 'interframe' | 'reference'
%                 'interframe': 帧间（frame_t vs frame_{t-1}）
%                 'reference':  参考帧（每帧 vs 首帧）
%   params      - 参数字典
%     .ssim_dynamicRange - SSIM 动态范围，默认 255
%
% OUTPUT:
%   psnr_mean   - 平均 PSNR (dB)
%   psnr_std    - PSNR 标准差
%   ssim_mean   - 平均 SSIM
%   ssim_std    - SSIM 标准差
%   per_frame   - struct，psnr_array(N-1×1), ssim_array(N-1×1)

function [psnr_mean, psnr_std, ssim_mean, ssim_std, per_frame] = compute_psnr_ssim(frames, method, params)
    arguments
        frames
        method char = 'interframe'
        params struct = struct()
    end

    if ~isfield(params, 'ssim_dynamicRange'), params.ssim_dynamicRange = 255; end

    % === 统一为 cell array ===
    if isnumeric(frames) && ndims(frames) == 4
        N = size(frames, 4);
        frames_cell = cell(1, N);
        for i = 1:N
            frames_cell{i} = frames(:,:,:,i);
        end
    elseif iscell(frames)
        N = numel(frames);
        frames_cell = frames;
    else
        error('frames 须为 H×W×3×N 数组或 cell array');
    end

    if N < 2
        warning('帧数不足 (<2)，无法计算帧间指标');
        psnr_mean = NaN; psnr_std = NaN;
        ssim_mean = NaN; ssim_std = NaN;
        per_frame = struct('psnr', [], 'ssim', []);
        return;
    end

    % === 逐帧计算 ===
    M = N - 1;  % 帧间对数量
    psnr_array = zeros(M, 1);
    ssim_array = zeros(M, 1);

    switch method
        case 'interframe'
            % 帧间对比：frame_t vs frame_{t-1}
            for i = 1:M
                psnr_array(i) = psnr(frames_cell{i+1}, frames_cell{i});
                ssim_array(i) = ssim(frames_cell{i+1}, frames_cell{i}, ...
                    'DynamicRange', params.ssim_dynamicRange);
            end

        case 'reference'
            % 参考帧对比：每帧 vs 首帧
            ref = frames_cell{1};
            for i = 2:N
                psnr_array(i-1) = psnr(frames_cell{i}, ref);
                ssim_array(i-1) = ssim(frames_cell{i}, ref, ...
                    'DynamicRange', params.ssim_dynamicRange);
            end

        otherwise
            error('不支持的方法: %s（应使用 interframe 或 reference）', method);
    end

    psnr_mean = mean(psnr_array, 'omitnan');
    psnr_std  = std(psnr_array, 'omitnan');
    ssim_mean = mean(ssim_array, 'omitnan');
    ssim_std  = std(ssim_array, 'omitnan');

    per_frame = struct('psnr', psnr_array, 'ssim', ssim_array);
end
