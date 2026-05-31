function setup_vlfeat()
    % SETUP_VLFEAT 自动配置 VLFeat 算法库
    % 如果当前环境尚未配置，则自动下载预编译包、解压并将其加入路径。
    
    vlfeat_url = 'https://www.vlfeat.org/download/vlfeat-0.9.21-bin.tar.gz';
    vlfeat_dir = fullfile(pwd, 'vlfeat-0.9.21');
    vlfeat_setup_file = fullfile(vlfeat_dir, 'toolbox', 'vl_setup.m');
    
    % 检查是否已经存在
    if exist(vlfeat_setup_file, 'file')
        disp('VLFeat 已存在，尝试加载...');
    else
        disp('未发现 VLFeat，正在下载预编译包...');
        tar_file = fullfile(pwd, 'vlfeat-0.9.21-bin.tar.gz');
        if ~exist(tar_file, 'file')
            websave(tar_file, vlfeat_url);
        end
        disp('正在解压 VLFeat...');
        untar(tar_file, pwd);
        disp('解压完成！');
    end
    
    % 针对 Apple Silicon (M1/M2/M3) 的自动源码编译
    if ismac && strcmp(mexext, 'mexmaca64')
        if ~exist(fullfile(vlfeat_dir, 'toolbox', 'mex', 'mexmaca64'), 'dir')
            disp('检测到 Apple Silicon 架构，开始执行原生源码编译 (耗时约十余秒)...');
            old_dir = pwd;
            cd(vlfeat_dir);
            % 调用 Makefile 编译 (依赖于已被我们修改过支持 maca64 的 Makefile)
            mex_path = fullfile(matlabroot, 'bin', 'mex');
            cmd = sprintf('make ARCH=maca64 MEX="%s" DISABLE_SSE2=yes DISABLE_AVX=yes', mex_path);
            [status, cmdout] = system(cmd);
            cd(old_dir);
            if status ~= 0
                warning('VLFeat 编译失败，请确保安装了 Xcode Command Line Tools: %s', cmdout);
            else
                disp('编译完成！');
            end
        end
    end
    
    % 尝试运行 vl_setup
    try
        run(vlfeat_setup_file);
        disp('VLFeat 环境配置成功！');
    catch ME
        warning('VLFeat 环境配置失败。如果在 Mac Apple Silicon (M1/M2/M3) 上运行，官方预编译可能不支持 arm64 架构。需要 Rosetta 2 或本地重新编译。');
        disp(ME.message);
    end
end
