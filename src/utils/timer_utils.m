%% timer_utils.m —— 计时工具
% 编码规范：参见项目根目录 AGENTS.md
% 通用工具，所有角色共用
%
% 功能：提供便捷的嵌套计时接口，用于统计各模块各阶段的耗时。
%
% 使用示例：
%   tm = TimerStack('main');
%   tm.tic('motion');
%   % ... 运动估计代码 ...
%   tm.toc('motion');
%   tm.tic('smooth');
%   % ... 平滑代码 ...
%   tm.toc('smooth');
%   tm.report();  % 打印所有计时

classdef TimerStack < handle
    properties
        name
        stacks      % containers.Map: label → [start_time, elapsed]
        active      % 当前活跃的计时 label 堆栈
    end

    methods
        function obj = TimerStack(name)
            obj.name = name;
            obj.stacks = containers.Map();
            obj.active = {};
        end

        function tic(obj, label)
            % 开始计时
            obj.active{end+1} = label;
            obj.stacks(label) = tic;
        end

        function elapsed = toc(obj, label)
            % 结束计时，返回耗时（秒）
            if ~obj.stacks.isKey(label)
                warning('TimerStack: 未找到计时标签 "%s"', label);
                elapsed = 0;
                return;
            end
            startTime = obj.stacks(label);
            elapsed = toc(startTime);
            obj.stacks(label) = elapsed;  % 存储耗时而非 tic 句柄
        end

        function report(obj)
            % 打印所有计时结果
            fprintf('=== 计时报告 [%s] ===\n', obj.name);
            keys_list = keys(obj.stacks);
            total = 0;
            for i = 1:numel(keys_list)
                k = keys_list{i};
                val = obj.stacks(k);
                if isscalar(val) && val > 0
                    fprintf('  %-20s: %8.2f ms\n', k, val * 1000);
                    total = total + val;
                end
            end
            fprintf('  %-20s: %8.2f ms\n', 'TOTAL', total * 1000);
        end

        function s = toStruct(obj)
            % 导出为 struct
            s = struct();
            keys_list = keys(obj.stacks);
            for i = 1:numel(keys_list)
                k = keys_list{i};
                val = obj.stacks(k);
                if isscalar(val)
                    s.(matlab.lang.makeValidName(k)) = val;
                end
            end
        end
    end
end
