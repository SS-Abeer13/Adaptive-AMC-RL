% headroom_v13  Stage 0 Headroom Check (PLAN_v13.md S0.1 - S0.3)
% Computes perfect-CSI upper bound (genie_cqi) and adaptivity bound
% (fixed_hindsight across -4:2) on evaluation traces of R1_pf and R2_edf.
% Checks reproduction of v12 Fixed values (R1 0.8461, R2 0.8693).
% Evaluates S0.3 gate: genie - Fixed >= +2% AND hindsight - Fixed >= +0.5%.

clear; clc;
root = 'D:\Adaptive AMC A2C+QL';
addpath(fullfile(root, 'Optimized', 'v13'));
cd(root);
v13_setup;

log_file = fullfile(root, 'Optimized', 'v13', 'logs', 'headroom_v13.log');
diary off;
if exist(log_file, 'file'), delete(log_file); end
diary(log_file);

out_file = fullfile(ds, 'headroom_v13.txt');
fid = fopen(out_file, 'w');
fprintf(fid, '# Stage 0 Headroom Check (PLAN_v13.md) - Generated %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, '# Gate: genie - Fixed >= +2.0%% AND hindsight - Fixed >= +0.5%%\n\n');
fclose(fid);

cases = {'R1_pf', C.R1_pf, 0.8461; 'R2_edf', C.R2_edf, 0.8693};
cand_offsets = -4:2;
nCands = numel(cand_offsets);

for cIdx = 1:size(cases, 1)
    tag = cases{cIdx, 1};
    raw_opts = cases{cIdx, 2};
    expected_fixed = cases{cIdx, 3};

    % Merge base into opts exactly as fill_campaign does
    opts = base;
    fn = fieldnames(raw_opts);
    for q = 1:numel(fn), opts.(fn{q}) = raw_opts.(fn{q}); end

    fprintf('\n========================================================================\n');
    fprintf('  STAGE 0: HEADROOM ANALYSIS FOR %s\n', tag);
    fprintf('========================================================================\n');

    % Build environment from defaults and options
    env = defaultEnv_v13(23, opts.N);
    fo = fieldnames(opts);
    for q = 1:numel(fo)
        if isfield(env, fo{q}) && ~isempty(opts.(fo{q})), env.(fo{q}) = opts.(fo{q}); end
    end
    env.max_delta = max(abs(env.actions));
    env.min_delta = -env.max_delta;
    eval_scheds = opts.eval_schedulers;
    env.calib_sched = eval_scheds{1};
    simTime = opts.simTime;
    nCalib = opts.n_calib;
    n_eval = opts.n_eval;
    traceSeedBase = opts.trace_seed_base;
    crnSeedBase = opts.crn_seed_base;

    % 1. Calibration of Fixed and FixedPU (disjoint calibration traces 60001+)
    fprintf('\nPhase 0: Calibrating Fixed, FixedPU, and Genie BLER on %d calibration traces...\n', nCalib);
    env = calibrateFixedClass_v13(env, nCalib, simTime);
    env = calibrateGenie_v13(env, nCalib, simTime);

    % 2. Rebuild the exact evaluation traces from v12 seeds
    fprintf('\nPhase 1: Rebuilding %d evaluation traces (traceBase=%d, crnBase=%d)...\n', ...
            n_eval, traceSeedBase, crnSeedBase);
    traces = struct('SINR', [], 'obsS', [], 'meta', [], 'U', []);
    traces(n_eval).SINR = [];
    for j = 1:n_eval
        rng(traceSeedBase + j);
        [Strue, ~, meta] = generateChannel_v13(simTime, env);
        obsS = cqiFeedback_v13(Strue, env, meta.delays);
        meta.trace_id = j;
        rng(crnSeedBase + j);
        traces(j).U = rand(simTime, env.N);
        traces(j).SINR = Strue;
        traces(j).obsS = obsS;
        traces(j).meta = meta;
    end

    % 3. Evaluate policies on the evaluation traces
    fprintf('Phase 2: Evaluating policies across %d traces...\n', n_eval);
    envE = env;
    envE.scheduler = eval_scheds{1};
    b0 = min(env.burn_in, simTime - 1);

    fixed_scores     = zeros(1, n_eval);
    fixedpu_scores   = zeros(1, n_eval);
    hindsight_scores = zeros(1, n_eval);
    hindsight_chosen = zeros(1, n_eval);
    genie_scores     = zeros(1, n_eval);

    t0 = tic;
    for j = 1:n_eval
        mt = traces(j).meta;

        % (a) Calibrated Fixed rule
        rng(77000 + 100*j + 10*5 + 1);
        [tp_f, ~, ~, ~, inf_f] = evalPolicy_v13('fixed', [], traces(j).SINR, traces(j).obsS, envE, mt, traces(j).U);
        [~, ~, fixed_scores(j)] = userMetric_v13(env, tp_f, inf_f, b0);

        % (b) FixedPU (Oracle per-class table)
        rng(77000 + 100*j + 10*6 + 1);
        [tp_pu, ~, ~, ~, inf_pu] = evalPolicy_v13('fixed_class', [], traces(j).SINR, traces(j).obsS, envE, mt, traces(j).U);
        [~, ~, fixedpu_scores(j)] = userMetric_v13(env, tp_pu, inf_pu, b0);

        % (c) Hindsight: evaluate every offset in -4:2 on this trace with CRN
        cand_sc = zeros(1, nCands);
        for oIdx = 1:nCands
            envO = envE;
            envO.fixed_offset = cand_offsets(oIdx);
            rng(77000 + 100*j + 10*5 + 1);
            [tp_o, ~, ~, ~, inf_o] = evalPolicy_v13('fixed', [], traces(j).SINR, traces(j).obsS, envO, mt, traces(j).U);
            [~, ~, cand_sc(oIdx)] = userMetric_v13(env, tp_o, inf_o, b0);
        end
        [best_sc, best_idx] = max(cand_sc);
        hindsight_scores(j) = best_sc;
        hindsight_chosen(j) = cand_offsets(best_idx);

        % (d) Genie (perfect-CSI bound)
        rng(77000 + 100*j + 10*5 + 1);
        [tp_g, ~, ~, ~, inf_g] = evalPolicy_v13('genie_cqi', [], traces(j).SINR, traces(j).obsS, envE, mt, traces(j).U);
        [~, ~, genie_scores(j)] = userMetric_v13(env, tp_g, inf_g, b0);

        if mod(j, 50) == 0 || j == n_eval
            fprintf('  Trace %3d/%3d: Fixed=%.4f, FixedPU=%.4f, Hindsight=%.4f (o=%+d), Genie=%.4f (elapsed %.1f min)\n', ...
                    j, n_eval, mean(fixed_scores(1:j)), mean(fixedpu_scores(1:j)), ...
                    mean(hindsight_scores(1:j)), cand_offsets(best_idx), mean(genie_scores(1:j)), toc(t0)/60);
        end
    end

    val_fixed     = mean(fixed_scores);
    val_fixedpu   = mean(fixedpu_scores);
    val_hindsight = mean(hindsight_scores);
    val_genie     = mean(genie_scores);

    % 4. Load a2c_v12 from results_v12_<tag>.mat
    v12_mat = fullfile(root, 'Optimized', 'v12', 'Dataset', sprintf('results_v12_%s.mat', tag));
    if exist(v12_mat, 'file')
        L12 = load(v12_mat, 'results');
        k_a2c = find(strcmpi(L12.results.schemes, 'Deep A2C v12'), 1);
        if isempty(k_a2c)
            k_a2c = find(contains(L12.results.schemes, 'Deep A2C'), 1);
        end
        val_a2c_v12 = mean(mean(L12.results.metrics(1).primary{k_a2c}, 1, 'omitnan'));
    else
        val_a2c_v12 = NaN;
    end

    % 5. Replication check
    fprintf('\nReplication Check for %s:\n', tag);
    fprintf('  Calibrated Fixed offset: %+d\n', env.fixed_offset);
    fprintf('  Calibrated FixedPU:      %s\n', mat2str(env.fixed_class_tab));
    fprintf('  Fixed On-Time Result:    %.4f (Expected: %.4f)\n', val_fixed, expected_fixed);
    if abs(val_fixed - expected_fixed) > 0.001
        warning('Fixed value for %s deviates from v12 (got %.4f, expected %.4f)', ...
                tag, val_fixed, expected_fixed);
    else
        fprintf('  [PASS] Fixed reproduction is verified!\n');
    end

    % 6. Gate S0.3 computation
    rel_genie = 100 * (val_genie - val_fixed) / val_fixed;
    rel_hindsight = 100 * (val_hindsight - val_fixed) / val_fixed;
    has_headroom = (rel_genie >= 2.0) && (rel_hindsight >= 0.5);

    fprintf('\nHeadroom Summary for %s:\n', tag);
    fprintf('  Fixed:              %.4f\n', val_fixed);
    fprintf('  FixedPU (Oracle):   %.4f\n', val_fixedpu);
    fprintf('  Deep A2C v12:       %.4f\n', val_a2c_v12);
    fprintf('  Hindsight (-4:2):   %.4f  (rel: %+.2f%% | gate >= +0.5%%)\n', val_hindsight, rel_hindsight);
    fprintf('  Genie (BLER=%.4f): %.4f  (rel: %+.2f%% | gate >= +2.0%%)\n', env.genie_bler, val_genie, rel_genie);
    fprintf('  Headroom Gate:      %s\n', char('FAIL' * ~has_headroom + 'PASS' * has_headroom));

    % Distribution of hindsight choices
    fprintf('  Hindsight offset distribution across traces:\n');
    for oIdx = 1:nCands
        frac = mean(hindsight_chosen == cand_offsets(oIdx));
        fprintf('    Offset %+2d: %5.1f%%\n', cand_offsets(oIdx), 100 * frac);
    end

    % 7. Write to Dataset/headroom_v13.txt
    fid = fopen(out_file, 'a');
    fprintf(fid, 'HEAD|%s|fixed=%.4f|fixedpu=%.4f|hindsight=%.4f|genie=%.4f|genie_bler=%.4f|a2c_v12=%.4f\n', ...
            tag, val_fixed, val_fixedpu, val_hindsight, val_genie, env.genie_bler, val_a2c_v12);
    fprintf(fid, 'GATE|%s|rel_genie=%+.2f%%|rel_hindsight=%+.2f%%|gate_pass=%d\n\n', ...
            tag, rel_genie, rel_hindsight, has_headroom);
    fclose(fid);
end

fprintf('\nStage 0 Complete. Results written to %s\n', out_file);
diary off;
