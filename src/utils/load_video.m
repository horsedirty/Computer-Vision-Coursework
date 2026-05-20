%% load_video.m —— 视频加载工具
% 编码规范：参见项目根目录 AGENTS.md
% 通用工具，所有角色共用
%
% 功能：读取视频文件，返回帧序列（cell array 或 4D array）
%
% INPUT:
%   videoPath   - 视频文件路径
%   params      - 参数字典
%     .startFrame  - 起始帧，默认 1
%     .maxFrames   - 最大帧数，默认 Inf
%     .asGrayscale  - 是否转灰度，默认 false
%     .outputFormat - 'cell' | 'array'，默认 'cell'
%
% OUTPUT:
%   frames      - cell array 或 H×W×C×N array
%   metadata    - struct，含 NumFrames, FrameRate, Width, Height, Duration

function [frames, metadata] = load_video(videoPath, params)
    arguments
        videoPath char
        params struct = struct()
    end

    if ~isfield(params, 'startFrame'),   params.startFrame = 1; end
    if ~isfield(params, 'maxFrames'),    params.maxFrames = Inf; end
    if ~isfield(params, 'asGrayscale'),  params.asGrayscale = false; end
    if ~isfield(params, 'outputFormat'), params.outputFormat = 'cell'; end

    if ~exist(videoPath, 'file')
        error('视频文件不存在: %s', videoPath);
    end

    v = VideoReader(videoPath);
    N_total = v.NumFrames;

    if isinf(params.maxFrames)
        N = N_total - params.startFrame + 1;
    else
        N = min(params.maxFrames, N_total - params.startFrame + 1);
    end

    fprintf('[load_video] %s: %d×%d, %d 帧, %.1f fps\n', ...
        videoPath, v.Width, v.Height, N, v.FrameRate);

    metadata = struct('NumFrames', N, 'FrameRate', v.FrameRate, ...
        'Width', v.Width, 'Height', v.Height, 'Duration', v.Duration);

    switch params.outputFormat
        case 'cell'
            frames = cell(N, 1);
            for i = 1:N
                frame = read(v, params.startFrame + i - 1);
                if params.asGrayscale && size(frame, 3) == 3
                    frame = rgb2gray(frame);
                end
                frames{i} = frame;
            end

        case 'array'
            % 预分配 4D 数组（注意：内存占用可能很大）
            firstFrame = read(v, params.startFrame);
            if params.asGrayscale && size(firstFrame, 3) == 3
                firstFrame = rgb2gray(firstFrame);
            end
            [H, W, C] = size(firstFrame);
            frames = zeros(H, W, C, N, 'uint8');
            frames(:,:,:,1) = firstFrame;
            for i = 2:N
                frame = read(v, params.startFrame + i - 1);
                if params.asGrayscale && size(frame, 3) == 3
                    frame = rgb2gray(frame);
                end
                frames(:,:,:,i) = frame;
            end

        otherwise
            error('不支持输出格式: %s', params.outputFormat);
    end
end
