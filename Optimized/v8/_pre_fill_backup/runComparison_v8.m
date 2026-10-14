function results = runComparison_v8(opts)
% runComparison_v8  v8 Evaluation and benchmarking harness:
% Calibrate, train autonomously from scratch, evaluate across 7 comparators,
% and perform rigorous statistical validation (Wilcoxon + TOST Equivalence).
    if nargin < 1, opts = struct(); end
    g = @(f, d) get_def(opts, f, d);

    Nopt          = g('N', 10);
    simTime       = g('simTime', 200);
    ep_deep       = g('ep_deep', 300);
    n_seeds       = g('n_seeds', 5);
    n_eval        = g('n_eval', 100); % Expanded from 30 to 100 traces
    baseSeed      = g('base_seed', 42);
    traceSeedBase = g('trace_seed_base', 9000);
    nCalib        = g('n_calib', 6);

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', 'v7'));
    addpath(fullfile(here, '..', 'v5'));
    addpath(fullfile(here, '..', 'case2_3'));

    env = defaultEnv_v8(23, Nopt);
    for f = {'hetero', 'burst_on', 'burst_IM_dB', 'burst_dwell_calm', ...
             'burst_dwell_burst', 'speed_switch', 'harq_on', 'harq_max_retx', ...
             'harq_comb_dB', 'state_tier', 'olla_warm_ttis', 'actions', ...
             'sigma_meas', 'speed', 'cqi_delay', 'delay_hom', 'use_gpu', ...
             'train_sched_weights', 'bc_warm_eps', 'fixed_cands', 'olla_target', ...
             'olla_off_lim', 'multi_olla_fast', 'multi_olla_slow', 'olla_step_down'}
        if isfield(opts, f{1}) && ~isempty(opts.(f{1})), env.(f{1}) = opts.(f{1}); end
    end
    eval_scheds = g('eval_schedulers', {'pf'});

    fprintf('========================================================================\n');
    fprintf('  RL-AMC v8 Master Comparison Campaign\n');
    fprintf('  N=%d | Hetero=%.2f | Burst=+%g dB | HARQ=%d | Tier=%s\n', ...
            env.N, env.hetero, env.burst_IM_dB, env.harq_on, env.state_tier);
    fprintf('  Seeds=%d | Traces=%d | Episodes=%d | SimTime=%d | Actions=%s\n', ...
            n_seeds, n_eval, ep_deep, simTime, mat2str(env.actions));
    fprintf('  Zero Behavior Cloning: bc_warm_eps = %d (Strictly Autonomous)\n', env.bc_warm_eps);
    fprintf('  Started: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    fprintf('========================================================================\n\n');

    % -------------------------------------------------------------
    % Phase 0: Calibrate Fixed-Offset Comparators
    % -------------------------------------------------------------
    env = calibrateFixedClass_v8(env, nCalib, simTime);

    % -------------------------------------------------------------
    % Phase 1: Autonomous Training from Scratch (Zero BC)
    % -------------------------------------------------------------
    fprintf('\nPHASE 1 -- Autonomous Training (%d seeds)\n', n_seeds);
    A2Cs = cell(1, n_seeds);
    lc_dac = zeros(ep_deep, n_seeds);
    ent_dac = zeros(ep_deep, n_seeds);

    for s = 1:n_seeds
        fprintf('  Seed %d/%d (%s)...\n', s, n_seeds, datestr(now, 'HH:MM:SS'));
        t0 = tic;
        [A2Cs{s}, ~, lc_dac(:, s), ent_dac(:, s)] = ...
            DeepA2C_Shared_v8(simTime, ep_deep, baseSeed + 200 + s, env);
        fprintf('    [Deep A2C v8] Finished in %7.1f s | Final CellTp = %5.2f Mbps\n', ...
                toc(t0), lc_dac(end, s));
    end

    % -------------------------------------------------------------
    % Phase 2: Held-Out Trace Generation (N >= 100 Traces)
    % -------------------------------------------------------------
    fprintf('\nPHASE 2 -- Evaluation on %d Held-Out Traces\n', n_eval);
    traces = struct('SINR', [], 'obsS', [], 'meta', []);
    traces(n_eval).SINR = [];
    for j = 1:n_eval
        rng(traceSeedBase + j);
        [Strue, ~, meta] = generateChannel_v7(simTime, env);
        obsS = cqiFeedback_v8(Strue, env, meta.delays);
        traces(j).SINR = Strue;
        traces(j).obsS = obsS;
        traces(j).meta = meta;
    end

    saveTag       = g('save_tag', 'headline');

    schemes = {'Baseline', 'OLLA', 'Warm-OLLA', 'Multi-OLLA', 'Fixed', 'Fixed-Online', 'FixedPU (Oracle)', 'Deep A2C v8'};
    ptypes  = {'baseline', 'olla', 'warm_olla', 'multi_olla', 'fixed', 'fixed_online', 'fixed_class',     'a2c_v8'};
    K = numel(schemes);
    detK = 7; % Schemes 1 to 7 are deterministic across seeds

    M_all = [];
    txtReport = sprintf('========================================================================\n');
    txtReport = [txtReport sprintf('RL-AMC v8 EVALUATION REPORT [%s]\n', upper(saveTag))];
    txtReport = [txtReport sprintf('N=%d | BW=20 MHz | RB=100 | NoiseFloor=%.1f dBm | Hetero=%.2f | Burst=+%g dB\n', ...
                           env.N, env.noise_floor_dBm, env.hetero, env.burst_IM_dB)];
    txtReport = [txtReport sprintf('HARQ=%d | StateTier=%s | Actions=%s | Zero-BC (bc_warm_eps=%d)\n', ...
                           env.harq_on, env.state_tier, mat2str(env.actions), env.bc_warm_eps)];
    txtReport = [txtReport sprintf('Seeds=%d | Traces=%d | SimTime=%d | Saved: %s\n', ...
                           n_seeds, n_eval, simTime, datestr(now, 'yyyy-mm-dd HH:MM:SS'))];
    txtReport = [txtReport sprintf('========================================================================\n\n')];

    for sc = 1:numel(eval_scheds)
        envE = env;
        envE.scheduler = eval_scheds{sc};
        M = init_metrics_v8(K, n_seeds, n_eval);
        fprintf('\n--- Evaluating Scheduler: %s ---\n', upper(envE.scheduler));
        txtReport = [txtReport sprintf('---- SCHEDULER: %s ----\n', upper(envE.scheduler))];

        for j = 1:n_eval
            mt = traces(j).meta;
            for k = 1:K
                if k <= detK, ns = 1; else, ns = n_seeds; end
                for s = 1:ns
                    pol = [];
                    if k == 8, pol = A2Cs{s}; end
                    rng(77000 + 100*j + 10*k + s);
                    [tp, bl, ce] = evalPolicy_v8(ptypes{k}, pol, ...
                                                 traces(j).SINR, traces(j).obsS, envE, mt);

                    b0 = min(env.burn_in, size(tp, 1) - 1);
                    tpB = tp(b0+1:end, :);
                    blB = bl(b0+1:end, :);
                    ceB = ce(b0+1:end, :);
                    bu  = mt.burst(b0+1:end);
                    pu  = mean(tpB, 1);

                    M.cell_tp{k}(s, j) = sum(pu);
                    M.edge_tp{k}(s, j) = prctile(pu, 5); % 5th-percentile cell-edge throughput
                    ok = ~isnan(blB);
                    if any(ok(:)), M.bler{k}(s, j) = mean(blB(ok)); else, M.bler{k}(s, j) = NaN; end
                    M.jain{k}(s, j) = sum(pu)^2 / (env.N * max(sum(pu.^2), eps));
                    M.cqie{k}(s, j) = mean(ceB(:));

                    if any(bu),  M.tp_burst{k}(s, j) = sum(mean(tpB(bu, :), 1));
                    else,        M.tp_burst{k}(s, j) = NaN; end
                    if any(~bu), M.tp_calm{k}(s, j)  = sum(mean(tpB(~bu, :), 1));
                    else,        M.tp_calm{k}(s, j)  = NaN; end
                end
            end
        end

        % -------------------------------------------------------------
        % Phase 3: Reporting, Wilcoxon Tests & TOST Equivalence
        % -------------------------------------------------------------
        hdr = sprintf('  %-20s | %-16s | %-8s | %-8s | %-8s | %-12s\n', ...
                      'Scheme', 'Cell Tp (Mbps)', 'BLER1', 'Edge Tp', 'Jain', 'Burst / Calm');
        sep = sprintf('----------------------------------------------------------------------------------------\n');
        fprintf('\n========================================================================================\n');
        fprintf('%s%s', hdr, sep);
        txtReport = [txtReport hdr sep];

        tp_all = cell(1, K);
        for k = 1:K
            if k <= detK
                tp_k = M.cell_tp{k}(1, :);
            else
                tp_k = mean(M.cell_tp{k}, 1);
            end
            tp_all{k} = tp_k;

            mean_tp = mean(tp_k);
            ci_tp   = 1.96 * std(tp_k) / sqrt(n_eval);
            mean_bl = metricMean_v8(M.bler{k},     k, detK);
            mean_ed = metricMean_v8(M.edge_tp{k},  k, detK);
            mean_jn = metricMean_v8(M.jain{k},     k, detK);
            mean_bu = metricMean_v8(M.tp_burst{k}, k, detK);
            mean_ca = metricMean_v8(M.tp_calm{k},  k, detK);

            row = sprintf('  %-20s | %5.2f +/- %4.2f   | %5.3f  | %5.2f   | %5.3f  | %4.2f / %4.2f Mbps\n', ...
                          schemes{k}, mean_tp, ci_tp, mean_bl, mean_ed, mean_jn, mean_bu, mean_ca);
            fprintf('%s', row);
            txtReport = [txtReport row];
        end
        eq_sep = sprintf('========================================================================================\n\n');
        fprintf('%s', eq_sep);
        txtReport = [txtReport eq_sep];

        % Statistical testing: Deep A2C (scheme 8) vs comparators
        tp_a2c = tp_all{8};
        st_hdr = sprintf('STATISTICAL SIGNIFICANCE & TOST EQUIVALENCE TESTING (A2C vs. Comparators):\n');
        fprintf('%s', st_hdr);
        txtReport = [txtReport st_hdr];

        % Raw paired Wilcoxon p-values for the 7-comparison family, then
        % Holm-Bonferroni adjustment (AUDIT FIX: the design plan and reports
        % state Holm correction, but only raw p-values were ever reported).
        p_raw = nan(1, 7);
        for k = 1:7
            if exist('signrank', 'file') == 2
                p_raw(k) = signrank(tp_a2c, tp_all{k});
            end
        end
        p_holm = holmAdjust_v8(p_raw);

        for k = 1:7
            tp_comp = tp_all{k};
            delta = tp_a2c - tp_comp;
            mean_diff = mean(delta);
            pct_gain  = 100 * mean_diff / max(mean(tp_comp), eps);
            p_wilc = p_raw(k);

            % Two One-Sided Tests (TOST) for Equivalence (margin: +/- 0.10 Mbps, ~2.5%)
            eq_margin = 0.10;
            se_diff = std(delta) / sqrt(n_eval);
            t1 = (mean_diff - (-eq_margin)) / (se_diff + eps);
            t2 = (eq_margin - mean_diff) / (se_diff + eps);
            p_tost1 = 1 - tcdf(t1, n_eval - 1);
            p_tost2 = 1 - tcdf(t2, n_eval - 1);
            p_equiv = max(p_tost1, p_tost2);

            equiv_str = 'NON-EQUIVALENT';
            if p_equiv < 0.05, equiv_str = 'EQUIVALENT'; end

            st_row = sprintf('  vs. %-18s : Delta = %+5.2f Mbps (%+5.1f%%) | Wilcoxon p = %7.4g (Holm %7.4g) | TOST p = %7.4g [%s]\n', ...
                             schemes{k}, mean_diff, pct_gain, p_wilc, p_holm(k), p_equiv, equiv_str);
            fprintf('%s', st_row);
            txtReport = [txtReport st_row];
        end
        txtReport = [txtReport sprintf('\n')];
        M_all = [M_all, M]; %#ok<AGROW>
    end

    % Package results
    results = struct('env', env, 'schemes', {schemes}, 'metrics', M_all, ...
                     'eval_schedulers', {eval_scheds}, ...
                     'policies', struct('A2C', {A2Cs}), ...
                     'learning_curves', lc_dac, 'entropy_curves', ent_dac);

    outDir = fullfile(here, 'Dataset');
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    matFile = fullfile(outDir, sprintf('results_v8_%s.mat', saveTag));
    txtFile = fullfile(outDir, sprintf('results_v8_%s.txt', saveTag));
    save(matFile, 'results', '-v7.3');

    fid = fopen(txtFile, 'w');
    if fid ~= -1
        fwrite(fid, txtReport);
        fclose(fid);
    end
    fprintf('\nResults successfully saved to:\n  MAT: %s\n  TXT: %s\n', matFile, txtFile);
end

function M = init_metrics_v8(K, n_seeds, n_eval)
    % AUDIT FIX: pre-allocate with NaN, not zeros. Deterministic schemes only
    % fill row 1, and zero-filled rows were being averaged into their stats.
    Z = nan(n_seeds, n_eval);
    M.cell_tp  = repmat({Z}, 1, K);
    M.edge_tp  = repmat({Z}, 1, K);
    M.bler     = repmat({Z}, 1, K);
    M.jain     = repmat({Z}, 1, K);
    M.cqie     = repmat({Z}, 1, K);
    M.tp_burst = repmat({Z}, 1, K);
    M.tp_calm  = repmat({Z}, 1, K);
end

function val = get_def(s, field, defaultVal)
    if isfield(s, field) && ~isempty(s.(field))
        val = s.(field);
    else
        val = defaultVal;
    end
end
