% run_v9_all  Headless entry point:
%   matlab -batch "run('D:\Adaptive AMC A2C+QL\Optimized\v9\run_v9_all.m')"
% Runs the preflight; if every preflight check passes, runs the full campaign.
fill_v9_preflight;
txt = fileread(fullfile('D:\Adaptive AMC A2C+QL\Optimized\v9', 'logs', 'fill_v9_preflight.txt'));
if contains(txt, '_FAIL')
    fprintf('PREFLIGHT FAILED - campaign not started. See logs/fill_v9_preflight.txt\n');
else
    clearvars -except txt
    fill_v9_campaign;
end
