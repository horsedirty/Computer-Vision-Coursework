%% load_video.m —— Video Loading Utility
% Coding standard: See project root AGENTS.md
% Common utility, shared by all roles
%
% Function: Read video file, return frame sequence (cell array or 4D array)
%
% INPUT:
%   videoPath   - Video file path
%   params      - Parameter dictionary
%     .startFrame  - Start frame, default 1
%     .maxFrames   - Max frames, default Inf
%     .asGrayscale  - Whether to convert to grayscale, default false
%     .outputFormat - 'cell' | 'array', default 'cell'
%
% OUTPUT:
%   frames      - cell array or H×W×C×N array
%   metadata    - struct, contains NumFrames, FrameRate, Width, Height, Duration

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
        error('Video file not found: %s', videoPath);
    end

    v = VideoReader(videoPath);
    N_total = v.NumFrames;

    if isinf(params.maxFrames)
        N = N_total - params.startFrame + 1;
    else
        N = min(params.maxFrames, N_total - params.startFrame + 1);
    end

    fprintf('[load_video] %s: %d×%d, %d frames, %.1f fps\n', ...
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
            % Preallocate 4D array (note: memory usage may be large)
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
            error('Unsupported output format: %s', params.outputFormat);
    end
end
