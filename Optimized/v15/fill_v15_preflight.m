% fill_v15_preflight  Tiny end-to-end run of all 3 v15 cases.
% Tests calibration, base-rule selection, training, validation, evaluation,
% replication analysis, feasibility checking, delayed credit logging, and RTT effect analysis.

root = 'D:\Adaptive AMC A2C+QL';
v15dir = fullfile(root, 'Optimized', 'v15');
addpath(v15dir); addpath(fullfile(root, 'Optimized', 'v5')); addpath(fullfile(root, 'Optimized', 'case2_3'));
v15_setup;

pf = fullfile(v15, 'logs', 'fill_v15_preflight.txt');
fid = fopen(pf, 'w'); fprintf(fid, 'V15 PREFLIGHT %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS')); fclose(fid);

cases = {'Z1_rtt8', 'Z2_rtt4', 'Z3_rtt8_loose'};

for q = 1:numel(cases)
    tag = ['pre_' cases{q}];
    fprintf('\n=== Running Preflight for %s (tag: %s) ===\n', cases{q}, tag);
    try
        o = base; ov = C.(cases{q}); fn = fieldnames(ov);
        for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
        o.simTime = 100; o.ep_deep = 2; o.n_seeds = 2; o.n_eval = 6; o.n_calib = 2; o.n_calib_ctx = 2;
        o.a2c.val_every = 1; o.a2c.n_val = 2;
        o.save_tag = tag;
        runComparison_v15(o);
        f = fullfile(ds, ['results_v15_' tag '.mat']);
        fid = fopen(pf, 'a');
        fill_stats_v15(f, tag, fid, 1);
        analyze_v15_replication(f, tag, fid, 1);
        fprintf(fid, 'PREFLIGHT_%s_OK\n', cases{q}); fclose(fid);
        fprintf('=== Preflight for %s PASSED ===\n', cases{q});
    catch ME
        fid = fopen(pf, 'a'); fprintf(fid, 'PREFLIGHT_%s_FAIL|%s\n', cases{q}, ME.message); fclose(fid);
        disp(getReport(ME, 'extended', 'hyperlinks', 'off'));
        error('fill_v15_preflight:fail', 'Preflight failed for %s: %s', cases{q}, ME.message);
    end
end

% Run and append RTT effect analysis
fid = fopen(pf, 'a');
analyze_v15_rtteff(fid, 'pre_');
fclose(fid);

% Verify feasibility lines exist
feasFile = fullfile(ds, 'feasibility_v15.txt');
if ~exist(feasFile, 'file')
    fprintf('Running feasibility_v15...\n');
    feasibility_v15;
end

% Parse validation checks
fprintf('\nChecking PREFLIGHT, REPL, LATECREDIT, and FEAS lines...\n');
pftxt = fileread(pf);
for q = 1:numel(cases)
    target = sprintf('REPL|pre_%s|', cases{q});
    if contains(pftxt, target)
        fprintf('  Found %s: OK\n', target);
    else
        error('fill_v15_preflight:missing_repl', 'Missing REPL line for pre_%s', cases{q});
    end

    target_late = sprintf('LATECREDIT|pre_%s|', cases{q});
    if contains(pftxt, target_late)
        fprintf('  Found %s: OK\n', target_late);
    else
        error('fill_v15_preflight:missing_latecredit', 'Missing LATECREDIT line for pre_%s', cases{q});
    end
end

if contains(pftxt, 'RTTEFF|Z1_rtt8|')
    fprintf('  Found RTTEFF analysis: OK\n');
else
    error('fill_v15_preflight:missing_rtteff', 'Missing RTTEFF analysis');
end

feasp = fileread(feasFile);
for q = 1:numel(cases)
    target = sprintf('FEAS|cell=%s|', cases{q});
    if contains(feasp, target)
        fprintf('  Found %s: OK\n', target);
    else
        error('fill_v15_preflight:missing_feas', 'Missing FEAS line for %s', cases{q});
    end
end

fprintf('\n=== ALL PREFLIGHT INTEGRATION CHECKS PASSED ===\n');
