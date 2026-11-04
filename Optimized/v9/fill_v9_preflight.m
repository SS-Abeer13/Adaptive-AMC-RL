% fill_v9_preflight  Tiny run of every new v9 code path (results discarded).
% Output: logs/fill_v9_preflight.txt  (look for PREFLIGHT_*_OK / _FAIL)
v9_setup;
pf = fopen(fullfile(v9, 'logs', 'fill_v9_preflight.txt'), 'w');
fprintf(pf, 'PREFLIGHT started %s | MATLAB %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), version);
tiny = base; tiny.simTime = 60; tiny.ep_deep = 2; tiny.n_seeds = 2; tiny.n_eval = 3; tiny.n_calib = 1;
try
    o = tiny; o.save_tag = 'pre_pf';
    runComparison_v9(o);
    f = fullfile(ds, 'results_v9_pre_pf.mat');
    fill_stats_v9(f, 'pre_pf', pf);
    fill_actions_sweep_v9(f, 'pre_pf', pf, 1, [0.1]);
    fill_sanity2_v9(f, 'pre_pf', pf);
    fprintf(pf, 'PREFLIGHT_PF_OK\n');
catch ME, fprintf(pf, 'PREFLIGHT_PF_FAIL|%s\n', getReport(ME, 'extended', 'hyperlinks', 'off')); end
try
    o = tiny; o.save_tag = 'pre_steady'; o.olla_warm_ttis = 50; o.train_warm_ttis = 50; o.calib_warm = true;
    runComparison_v9(o);
    fill_stats_v9(fullfile(ds, 'results_v9_pre_steady.mat'), 'pre_steady', pf);
    fprintf(pf, 'PREFLIGHT_STEADY_OK\n');
catch ME, fprintf(pf, 'PREFLIGHT_STEADY_FAIL|%s\n', getReport(ME, 'extended', 'hyperlinks', 'off')); end
try
    o = tiny; o.save_tag = 'pre_eq'; o.eval_schedulers = {'eq'}; o.train_sched_weights = [0 0 1];
    runComparison_v9(o);
    f = fullfile(ds, 'results_v9_pre_eq.mat');
    fill_stats_v9(f, 'pre_eq', pf);
    fill_actions_sweep_v9(f, 'pre_eq', pf, 1, []);
    fprintf(pf, 'PREFLIGHT_EQ_OK\n');
catch ME, fprintf(pf, 'PREFLIGHT_EQ_FAIL|%s\n', getReport(ME, 'extended', 'hyperlinks', 'off')); end
try
    o = tiny; o.n_calib = 1;
    fill_bc_diag_v9(o, 1, 2, 2, 3, pf);
    fprintf(pf, 'PREFLIGHT_BC_OK\n');
catch ME, fprintf(pf, 'PREFLIGHT_BC_FAIL|%s\n', getReport(ME, 'extended', 'hyperlinks', 'off')); end
% CRN check: OLLA and Fixed with offset 0 must give identical throughput
try
    env = defaultEnv_v9(23, 10); env.olla_off_lim = 10; env.fixed_offset = 0;
    rng(9001); [S, ~, meta] = generateChannel_v9(200, env); O = cqiFeedback_v9(S, env, meta.delays);
    meta.trace_id = 1; rng(50001); U = rand(size(S));
    rng(1); a = evalPolicy_v9('olla', [], S, O, env, meta, U);
    rng(2); b = evalPolicy_v9('fixed', [], S, O, env, meta, U);
    fprintf(pf, 'CRNCHECK|olla=%.6f|fixed0=%.6f|identical=%d\n', sum(mean(a)), sum(mean(b)), isequal(a, b));
    rng(9002); [~, dist] = generateChannel_v9(200, env);
    fprintf(pf, 'MOBCHECK|max_step_m=%.4f (expect <= 0.03 with mob_kappa=1)\n', max(max(abs(diff(dist)))));
    fprintf(pf, 'PREFLIGHT_CRN_OK\n');
catch ME, fprintf(pf, 'PREFLIGHT_CRN_FAIL|%s\n', getReport(ME, 'extended', 'hyperlinks', 'off')); end
fprintf(pf, 'PREFLIGHT finished %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fclose(pf);
