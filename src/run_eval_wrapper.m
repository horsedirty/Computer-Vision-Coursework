%% Wrapper to run evaluation and capture output
init_project;
diary('F:\computer vision\test\Computer-Vision-Coursework\eval_log.txt');
diary on;
try
    run_full_evaluation;
catch e
    disp('=== ERROR OCCURRED ===');
    disp(getReport(e));
end
diary off;
exit;
