% fill_v13_preflight  Tiny end-to-end run of all three v13 cases (S1.6 Test 5).
% Verifies the full pipeline: calibration, base-rule selection, DeepA2C training,
% validation checkpointing, ensemble evaluation, stats, and replication analyzer.

v13_setup;
pf = fullfile(v13, 'logs', 'fill_v13_preflight.txt');
fid = fopen(pf, 'w'); fprintf(fid, 'V13 PREFLIGHT %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS')); fclose(fid);
names = {'X1_pf', 'X1_edf', 'X2_pf_shaped'};

for q = 1:numel(names)
    tag = ['pre_' names{q}];
    fprintf('\n=== Running Preflight for %s (tag: %s) ===\n', names{q}, tag);
    try
        o = base; ov = C.(names{q}); fn = fieldnames(ov);
        for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
        o.simTime = 100; o.ep_deep = 2; o.n_seeds = 2; o.n_eval = 6; o.n_calib = 2; o.n_calib_ctx = 2;
        o.a2c.val_every = 1; o.a2c.n_val = 2;
        o.save_tag = tag;
        runComparison_v13(o);
        f = fullfile(ds, ['results_v13_' tag '.mat']);
        fid = fopen(pf, 'a');
        fill_stats_v13(f, tag, fid, 1);
        analyze_v13_replication(f, tag, fid, 1);
        fprintf(fid, 'PREFLIGHT_%s_OK\n', names{q}); fclose(fid);
        fprintf('=== Preflight for %s PASSED ===\n', names{q});
    catch ME
        fid = fopen(pf, 'a'); fprintf(fid, 'PREFLIGHT_%s_FAIL|%s\n', names{q}, ME.message); fclose(fid);
        disp(getReport(ME, 'extended', 'hyperlinks', 'off'));
        error('fill_v13_preflight:fail', 'Preflight failed for %s: %s', names{q}, ME.message);
    end
end

fprintf('\nChecking REPL| lines in %s...\n', pf);
pftxt = fileread(pf);
for q = 1:numel(names)
    target = sprintf('REPL|pre_%s|', names{q});
    if contains(pftxt, target)
        fprintf('  Found %s: OK\n', target);
    else
        error('fill_v13_preflight:missing_repl', 'Missing REPL| line for pre_%s', names{q});
    end
end
fprintf('=== ALL PREFLIGHT RUNS PASSED AND REPL LINES VERIFIED ===\n');
