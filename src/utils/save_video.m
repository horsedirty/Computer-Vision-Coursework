%% save_video.m —— Video Saving Utility
% Coding standard: See project root AGENTS.md
% Common utility, shared by all roles
%
% Function: Encode frame sequence (cell array or 4D array) into .mp4 video file
%
% INPUT:
%   videoPath   - Output path
%   frames      - cell array or H×W×C×N array
%   frameRate   - Frame rate, default 30
%   params      - Parameter dictionary
%     .profile  - 'MPEG-4' | 'Motion JPEG AVI', default 'MPEG-4'
%     .quality  - Quality 0-100, default 95

function save_video(videoPath, frames, frameRate, params)
    arguments
        videoPath char
        frames
        frameRate (1,1) double = 30
        params struct = struct()
    end

    if ~isfield(params, 'profile'), params.profile = 'MPEG-4'; end
    if ~isfield(params, 'quality'), params.quality = 95; end

    % Ensure output directory exists
    outDir = fileparts(videoPath);
    if ~isempty(outDir) && ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    % 确定帧数
    if iscell(frames)
        N = numel(frames);
        firstFrame = frames{1};
    elseif ndims(frames) == 4
        N = size(frames, 4);
        firstFrame = frames(:,:,:,1);
    else
        error('frames must be cell array or H×W×C×N array');
    end

    v = VideoWriter(videoPath, params.profile);
    v.FrameRate = frameRate;

    if isprop(v, 'Quality')
        v.Quality = params.quality;
    end

    open(v);

    for i = 1:N
        if iscell(frames)
            writeVideo(v, frames{i});
        else
            writeVideo(v, frames(:,:,:,i));
        end
    end

    close(v);
    fprintf('[save_video] Saved: %s (%d frames, %.1f fps)\n', videoPath, N, frameRate);
end
