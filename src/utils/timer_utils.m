%% timer_utils.m —— Timing Utility
% Coding standard: See project root AGENTS.md
% Common utility, shared by all roles
%
% Function: Provides a convenient nested timing interface for measuring elapsed time of each module and stage.
%
% Usage example:
%   tm = TimerStack('main');
%   tm.tic('motion');
%   % ... motion estimation code ...
%   tm.toc('motion');
%   tm.tic('smooth');
%   % ... smoothing code ...
%   tm.toc('smooth');
%   tm.report();  % Print all timing

classdef TimerStack < handle
    properties
        name
        stacks      % containers.Map: label → [start_time, elapsed]
        active      % Currently active timing label stack
    end

    methods
        function obj = TimerStack(name)
            obj.name = name;
            obj.stacks = containers.Map();
            obj.active = {};
        end

        function tic(obj, label)
            % Start timing
            obj.active{end+1} = label;
            obj.stacks(label) = tic;
        end

        function elapsed = toc(obj, label)
            % End timing, returns elapsed time (seconds)
            if ~obj.stacks.isKey(label)
                warning('TimerStack: Timing label "%s" not found', label);
                elapsed = 0;
                return;
            end
            startTime = obj.stacks(label);
            elapsed = toc(startTime);
            obj.stacks(label) = elapsed;  % Store elapsed time instead of tic handle
        end

        function report(obj)
            % Print all timing results
            fprintf('=== Timing Report [%s] ===\n', obj.name);
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
            % Export as struct
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
