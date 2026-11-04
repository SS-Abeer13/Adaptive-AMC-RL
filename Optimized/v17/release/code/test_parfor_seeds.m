% test_parfor_seeds.m
% Verifies that running training seeds in parfor produces BIT-IDENTICAL
% results to serial training.
root = 'D:\Adaptive AMC A2C+QL';
addpath(fullfile(root, 'Optimized', 'v17'));
addpath(fullfile(root, 'Optimized', 'v5'));
addpath(fullfile(root, 'Optimized', 'case2_3'));

fprintf('=== test_parfor_seeds: Testing serial vs parfor bit-identity ===\n');

env = defaultEnv_v17(23, 10);
env.traffic = 'deadline';
env.pkt_bits = 12000;
env.pkt_period = 20;
env.pkt_deadline = 10;
env.harq_rtt = 0;
env.harq_nproc = 1;
env.pf_avg = 'scheduled';
env.drain = true;
env.useful_bits = true;
env.action_mode = 'resid';
env.resid_actions = [-1 0 1];
env.actions = -4:2;
env.max_delta = 4; env.min_delta = -4;

simTime = 100;
ep_deep = 5;
n_seeds = 2;
baseSeed = 30042;

% 1. Serial run
fprintf('Running 2 seeds in SERIAL...\n');
A2C_serial = cell(1, n_seeds);
lc_serial  = zeros(ep_deep, n_seeds);
for s = 1:n_seeds
    [A2C_serial{s}, ~, lc_serial(:, s)] = DeepA2C_Shared_v17(simTime, ep_deep, baseSeed + 200 + s, env);
end

% 2. Parfor run
fprintf('Running 2 seeds in PARFOR (2 workers)...\n');
p = gcp('nocreate');
if isempty(p), parpool('local', 2); end

A2C_parfor = cell(1, n_seeds);
lc_parfor  = zeros(ep_deep, n_seeds);
parfor s = 1:n_seeds
    [a2c_s, ~, lc_s] = DeepA2C_Shared_v17(simTime, ep_deep, baseSeed + 200 + s, env);
    A2C_parfor{s} = a2c_s;
    lc_parfor(:, s) = lc_s;
end

% 3. Check bit-identical
allIdentical = true;
maxDiffW = 0;
maxDiffLC = max(abs(lc_serial(:) - lc_parfor(:)));

for s = 1:n_seeds
    fnames = fieldnames(A2C_serial{s});
    for f = 1:numel(fnames)
        fn = fnames{f};
        v1 = A2C_serial{s}.(fn);
        v2 = A2C_parfor{s}.(fn);
        if isnumeric(v1)
            diff = max(abs(v1(:) - v2(:)));
            if diff > maxDiffW, maxDiffW = diff; end
            if diff > 0, allIdentical = false; end
        end
    end
end

fprintf('Max difference in trained weights: %.2e\n', maxDiffW);
fprintf('Max difference in learning curves: %.2e\n', maxDiffLC);

if allIdentical && maxDiffLC == 0
    fprintf('\n=== test_parfor_seeds: ALL CHECKS PASSED -- BIT IDENTICAL! ===\n');
else
    error('test_parfor_seeds:fail', 'Differences found between serial and parfor!');
end
