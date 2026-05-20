%% gaussian_smooth.m —— 基线高斯平滑
% 编码规范：参见项目根目录 AGENTS.md
% 角色四 & 五协作实现
%
% 功能：对绝对坐标下的仿射参数序列做简单的高斯/IIR 低通滤波。
% 这是消融实验中的 baseline 方案——效果不如马尔可夫平滑，但实现简单，
% 用来证明相对坐标 + 窗口约束带来的增益。
%
% INPUT:
%   paramAbsolute - N×6，绝对坐标仿射参数序列
%   params        - 参数字典
%     .sigma         - 高斯核标准差，默认 5（帧）
%     .method        - 'gaussian' | 'butterworth' | 'smoothdata'
%                      默认 'gaussian'
%     .cutoff_order  - Butterworth 滤波器阶数（仅 method='butterworth'），默认 4
%
% OUTPUT:
%   paramSmoothed - N×6，平滑后参数序列
%   diagnostics   - struct
%
% TODO:
%   [ ] 实现 imgaussfilt 的一维对应物（用 conv 手动实现高斯平滑）
%   [ ] 实现 MATLAB smoothdata 调用（最简单的 baseline）
%   [ ] 实现 Butterworth IIR 滤波器（'butter' + 'filtfilt' 零相位滤波）
%   [ ] 绘制平滑前后对比图，标注"过平滑危险区"（sigma 太大导致有意运动也被抹掉）

function [paramSmoothed, diagnostics] = gaussian_smooth(paramAbsolute, params)
    arguments
        paramAbsolute (:,6) double
        params struct = struct()
    end

    if ~isfield(params, 'sigma'),        params.sigma = 5; end
    if ~isfield(params, 'method'),       params.method = 'gaussian'; end
    if ~isfield(params, 'cutoff_order'), params.cutoff_order = 4; end

    N = size(paramAbsolute, 1);
    paramSmoothed = zeros(N, 6);
    sigma = params.sigma;

    switch params.method
        case 'gaussian'
            % TODO: 对每一列独立做高斯卷积
            % 生成高斯核: kernel = exp(-(-3*sigma:3*sigma).^2 / (2*sigma^2)); kernel = kernel / sum(kernel);
            % 对每列: paramSmoothed(:,j) = conv(paramAbsolute(:,j), kernel, 'same');
            paramSmoothed = paramAbsolute;  % 占位

        case 'butterworth'
            % TODO: 设计 Butterworth 低通滤波器
            % [b, a] = butter(cutoff_order, cutoff_freq/(fs/2), 'low');
            % 对每列: paramSmoothed(:,j) = filtfilt(b, a, paramAbsolute(:,j));
            paramSmoothed = paramAbsolute;

        case 'smoothdata'
            % TODO: 直接用 MATLAB 内置
            % for j = 1:6
            %     paramSmoothed(:,j) = smoothdata(paramAbsolute(:,j), 'gaussian', sigma);
            % end
            paramSmoothed = paramAbsolute;

        otherwise
            error('不支持的平滑方法: %s', params.method);
    end

    % 诊断：平滑前后的方差衰减比
    var_before = var(paramAbsolute, 0, 1);
    var_after  = var(paramSmoothed, 0, 1);
    diagnostics = struct(...
        'method', params.method, ...
        'sigma', sigma, ...
        'var_reduction_ratio', mean(var_after ./ var_before));
end
