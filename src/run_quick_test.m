% Quick test script to find errors
disp('=== Starting Quick Test ===');
init_project;

params = struct();
params.inputVideo = fullfile('..', 'data', 'test_videos', 'test1.mp4');

% Run the main pipeline first
try
    main_pipeline(params);
    disp('=== MAIN PIPELINE PASSED ===');
catch e
    disp('=== MAIN PIPELINE FAILED ===');
    disp(getReport(e));
end

disp('=== Quick Test Complete ===');
