% run_v15_resume  Entry point for the headless launcher (also used after a crash):
% finished points and trained seeds (Dataset/ckpt) are reused.
root = 'D:\Adaptive AMC A2C+QL';
addpath(fullfile(root, 'Optimized', 'v15'));
fill_v15_campaign;
