% run_v10_all  Headless entry point (preflight, then campaign if it passes).
fill_v10_preflight;
txt = fileread(fullfile('D:\Adaptive AMC A2C+QL\Optimized\v10', 'logs', 'fill_v10_preflight.txt'));
if contains(txt, '_FAIL')
    fprintf('PREFLIGHT FAILED - campaign not started. See logs/fill_v10_preflight.txt\n');
else
    clearvars -except txt
    fill_v10_campaign;
end
