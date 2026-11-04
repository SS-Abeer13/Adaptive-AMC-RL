% run_v11_all  Headless entry point (preflight, then campaign if it passes).
fill_v11_preflight;
txt = fileread(fullfile('D:\Adaptive AMC A2C+QL\Optimized\v11', 'logs', 'fill_v11_preflight.txt'));
if contains(txt, '_FAIL')
    fprintf('PREFLIGHT FAILED - campaign not started. See logs/fill_v11_preflight.txt\n');
else
    clearvars -except txt
    fill_v11_campaign;
end
