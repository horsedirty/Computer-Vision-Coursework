function run_quick_test2()
    diary('../test_output5.txt');
    disp('=== Quick Test Starting ===');
    disp(datetime('now'));
    try
        run_quick_test;
    catch e
        disp('ERROR:');
        disp(getReport(e));
    end
    disp('=== Quick Test Done ===');
    diary off;
end
