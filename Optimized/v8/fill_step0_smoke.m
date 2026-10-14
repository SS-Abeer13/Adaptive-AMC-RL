% fill_step0_smoke  Smoke test + timing probe for the corrected v8 re-run.
root = 'D:\Adaptive AMC A2C+QL';
cd(root);
logf = fullfile(root, 'Optimized', 'v8', 'logs', 'fill_step0_smoke.log');
diary off; if exist(logf, 'file'), delete(logf); end
diary(logf);
addpath(fullfile(root, 'Optimized', 'v8'));
fprintf('START %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
t = tic;
try
    test_v8_smoke;
    fprintf('SMOKE_OK %.1f s\n', toc(t));
catch ME
    fprintf('SMOKE_FAIL\n%s\n', getReport(ME, 'extended', 'hyperlinks', 'off'));
end
t = tic;
try
    o = struct('N', 10, 'simTime', 200, 'ep_deep', 10, 'n_seeds', 1, 'n_eval', 3, ...
               'n_calib', 2, 'eval_schedulers', {{'pf'}}, 'save_tag', 'timing_probe');
    runComparison_v8(o);
    fprintf('TIMING_OK %.1f s\n', toc(t));
catch ME
    fprintf('TIMING_FAIL\n%s\n', getReport(ME, 'extended', 'hyperlinks', 'off'));
end
fprintf('END %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
diary off;
