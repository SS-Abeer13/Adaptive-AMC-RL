% fill_v14_preflight  Tiny end-to-end run of all 6 v14 cases (Test B3.4).
% Tests calibration, training, validation, evaluation, replication analysis,
% paired shaping analysis, and feasibility checking.

root = 'D:\Adaptive AMC A2C+QL';
v14dir = fullfile(root, 'Optimized', 'v14');
addpath(v14dir); addpath(fullfile(root, 'Optimized', 'v5')); addpath(fullfile(root, 'Optimized', 'case2_3'));
v14_setup;

pf = fullfile(v14, 'logs', 'fill_v14_preflight.txt');
fid = fopen(pf, 'w'); fprintf(fid, 'V14 PREFLIGHT %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS')); fclose(fid);

cases = {'Y0_base', 'Y0_noshape', 'Y1_lo_tight', 'Y2_lo_loose', 'Y3_hi_tight', 'Y4_hi_loose'};

for q = 1:numel(cases)
    tag = ['pre_' cases{q}];
    fprintf('\n=== Running Preflight for %s (tag: %s) ===\n', cases{q}, tag);
    try
        o = base; ov = C.(cases{q}); fn = fieldnames(ov);
        for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
        o.simTime = 100; o.ep_deep = 2; o.n_seeds = 2; o.n_eval = 6; o.n_calib = 2; o.n_calib_ctx = 2;
        o.a2c.val_every = 1; o.a2c.n_val = 2;
        o.save_tag = tag;
        runComparison_v14(o);
        f = fullfile(ds, ['results_v14_' tag '.mat']);
        fid = fopen(pf, 'a');
        fill_stats_v14(f, tag, fid, 1);
        analyze_v14_replication(f, tag, fid, 1);
        fprintf(fid, 'PREFLIGHT_%s_OK\n', cases{q}); fclose(fid);
        fprintf('=== Preflight for %s PASSED ===\n', cases{q});
    catch ME
        fid = fopen(pf, 'a'); fprintf(fid, 'PREFLIGHT_%s_FAIL|%s\n', cases{q}, ME.message); fclose(fid);
        disp(getReport(ME, 'extended', 'hyperlinks', 'off'));
        error('fill_v14_preflight:fail', 'Preflight failed for %s: %s', cases{q}, ME.message);
    end
end

% Run paired shaping test between pre_Y0_base and pre_Y0_noshape
fprintf('\n=== Running Paired Shaping Test for Preflight ===\n');
fBase = fullfile(ds, 'results_v14_pre_Y0_base.mat');
fNoShape = fullfile(ds, 'results_v14_pre_Y0_noshape.mat');
fid = fopen(pf, 'a');
shaping_pair_v14(fBase, fNoShape, fid);
fclose(fid);

% Verify feasibility lines exist
feasFile = fullfile(ds, 'feasibility_v14.txt');
if ~exist(feasFile, 'file')
    fprintf('Running feasibility_v14...\n');
    feasibility_v14;
end

% Parse validation checks
fprintf('\nChecking PREFLIGHT, REPL, SHAPE and FEAS lines...\n');
pftxt = fileread(pf);
for q = 1:numel(cases)
    target = sprintf('REPL|pre_%s|', cases{q});
    if contains(pftxt, target)
        fprintf('  Found %s: OK\n', target);
    else
        error('fill_v14_preflight:missing_repl', 'Missing REPL line for pre_%s', cases{q});
    end
end

if contains(pftxt, 'SHAPE|')
    fprintf('  Found SHAPE| line: OK\n');
else
    error('fill_v14_preflight:missing_shape', 'Missing SHAPE line');
end

feasp = fileread(feasFile);
for q = 1:numel(cases)
    target = sprintf('FEAS|cell=%s|', cases{q});
    if contains(feasp, target)
        fprintf('  Found %s in feasibility: OK\n', target);
    else
        error('fill_v14_preflight:missing_feas', 'Missing FEAS line for %s', cases{q});
    end
end

fprintf('\n=== ALL B3 TESTS AND PREFLIGHT VERIFICATIONS PASSED ===\n');
