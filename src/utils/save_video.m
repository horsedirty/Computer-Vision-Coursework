%% save_video.m —— 视频保存工具
% 编码规范：参见项目根目录 AGENTS.md
% 通用工具，所有角色共用
%
% 功能：将帧序列（cell array 或 4D array）编码为 .mp4 视频文件
%
% INPUT:
%   videoPath   - 输出路径
%   frames      - cell array 或 H×W×C×N array
%   frameRate   - 帧率，默认 30
%   params      - 参数字典
%     .profile  - 'MPEG-4' | 'Motion JPEG AVI'，默认 'MPEG-4'
%     .quality  - 质量 0-100，默认 95

function save_video(videoPath, frames, frameRate, params)
    arguments
        videoPath char
        frames
        frameRate (1,1) double = 30
        params struct = struct()
    end

    if ~isfield(params, 'profile'), params.profile = 'MPEG-4'; end
    if ~isfield(params, 'quality'), params.quality = 95; end

    % 确保输出目录存在
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
        error('frames 须为 cell array 或 H×W×C×N array');
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
    fprintf('[save_video] 已保存: %s (%d 帧, %.1f fps)\n', videoPath, N, frameRate);
end
