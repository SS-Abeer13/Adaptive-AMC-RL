function results = runComparison_v12(opts)
% runComparison_v12  v8 Evaluation and benchmarking harness:
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
    crnSeedBase   = g('crn_seed_base', 50000);  % T2 (PLAN_v12_replication.md): default keeps v11 behaviour
    nCalib        = g('n_calib', 6);
    % P2 (IMPLEMENTATION_PLAN_v12.md): also train and report a PPO policy
    % ("Deep PPO v12") alongside A2C ("keep A2C for comparison"). Off by
    % default -- existing offset/target-mode A2C-only campaigns unaffected.
    trainPPO      = g('train_ppo', false);
    epDeepPPO     = g('ep_deep_ppo', ep_deep);
    % P4 (IMPLEMENTATION_PLAN_v12.md, scoped per README_v12.md): also train
    % and report a GRU recurrent policy ("Deep GRU v12"), offset action
    % space, A2C-style 16-step truncated-BPTT update. Off by default.
    trainGRU      = g('train_gru', false);
    epDeepGRU     = g('ep_deep_gru', ep_deep);

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', 'v7'));
    addpath(fullfile(here, '..', 'v5'));
    addpath(fullfile(here, '..', 'case2_3'));

    env = defaultEnv_v12(23, Nopt);
    % v12: every option whose name is an env field overrides that field
    fo = fieldnames(opts);
    for q = 1:numel(fo)
        if isfield(env, fo{q}) && ~isempty(opts.(fo{q})), env.(fo{q}) = opts.(fo{q}); end
    end
    % keep the action-dependent limits consistent with a narrowed action set
    env.max_delta = max(abs(env.actions)); env.min_delta = -env.max_delta;
    eval_scheds = g('eval_schedulers', {'pf'});
    env.calib_sched = eval_scheds{1};   % v9: calibrate on the evaluated scheduler

    fprintf('========================================================================\n');
    fprintf('  RL-AMC v8 Master Comparison Campaign\n');
    fprintf('  N=%d | Hetero=%.2f | Burst=+%g dB | HARQ=%d | Tier=%s\n', ...
            env.N, env.hetero, env.burst_IM_dB, env.harq_on, env.state_tier);
    fprintf('  Seeds=%d | Traces=%d | Episodes=%d | SimTime=%d | Actions=%s\n', ...
            n_seeds, n_eval, ep_deep, simTime, mat2str(env.actions));
    fprintf('  Zero Behavior Cloning: bc_warm_eps = %d (Strictly Autonomous)\n', env.bc_warm_eps);
    fprintf('  Started: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    fprintf('========================================================================\n\n');

    % P1 (README_v12.md): action_mode = 'target' repurposes the A2C action
    % as an OLLA target-BLER arm; default 'offset' is the v9/v10/v12-P0 path.
    targMode = isfield(env, 'action_mode') && strcmpi(env.action_mode, 'target');

    % -------------------------------------------------------------
    % Phase 0: Calibrate Fixed-Offset Comparators
    % -------------------------------------------------------------
    env = calibrateFixedClass_v12(env, nCalib, simTime);
    env = calibrateCtx_v12(env, env.n_calib_ctx, simTime);
    if targMode
        % P1 same-information comparator: per-class tuned target (the
        % target-mode analogue of FixedPU).
        env = calibrateTargetClass_v12(env, nCalib, simTime);
    end

    % -------------------------------------------------------------
    % Phase 1: Autonomous Training from Scratch (Zero BC)
    % -------------------------------------------------------------
    fprintf('\nPHASE 1 -- Autonomous Training (%d seeds)\n', n_seeds);
    A2Cs = cell(1, n_seeds);
    Bs   = cell(1, n_seeds);  % P0.4: best-on-validation checkpoint (scheme 8b)
    valCurves = cell(1, n_seeds);  % P0.5: validation-score curve (empty if val_every = 0)
    lc_dac = zeros(ep_deep, n_seeds);
    Bg = cell(1, n_seeds); Bd = cell(1, n_seeds);
    Bt = cell(1, n_seeds);  % P1: contextual bandit over targets (target-mode only)
    lc_bg = zeros(ep_deep, n_seeds); lc_bd = zeros(ep_deep, n_seeds); lc_bt = zeros(ep_deep, n_seeds);
    ent_dac = zeros(ep_deep, n_seeds);
    Ps = cell(1, n_seeds);  % P2: Deep PPO v12 (trainPPO only)
    lc_ppo = zeros(epDeepPPO, n_seeds); ent_ppo = zeros(epDeepPPO, n_seeds);
    Gs = cell(1, n_seeds);  % P4: Deep GRU v12 (trainGRU only)
    lc_gru = zeros(epDeepGRU, n_seeds); ent_gru = zeros(epDeepGRU, n_seeds);

    for s = 1:n_seeds
        fprintf('  Seed %d/%d (%s)...\n', s, n_seeds, datestr(now, 'HH:MM:SS'));
        t0 = tic;
        % v12: per-seed checkpoint (survives a MATLAB crash; deleted only by hand)
        ck = fullfile(here, 'Dataset', 'ckpt', sprintf('%s_seed%d.mat', g('save_tag', 'headline'), s));
        if exist(ck, 'file')
            Lc = load(ck); A2Cs{s} = Lc.a2c; lc_dac(:, s) = Lc.lc; ent_dac(:, s) = Lc.ent;
            if isfield(Lc, 'abest'), Bs{s} = Lc.abest; else, Bs{s} = Lc.a2c; end
            if isfield(Lc, 'valc'), valCurves{s} = Lc.valc; else, valCurves{s} = []; end
            Bg{s} = Lc.bg; lc_bg(:, s) = Lc.lbg; Bd{s} = Lc.bd; lc_bd(:, s) = Lc.lbd;
            if targMode && isfield(Lc, 'bt'), Bt{s} = Lc.bt; lc_bt(:, s) = Lc.lbt; end
            if trainPPO && isfield(Lc, 'ppo'), Ps{s} = Lc.ppo; lc_ppo(:, s) = Lc.lcppo; ent_ppo(:, s) = Lc.entppo; end
            if trainGRU && isfield(Lc, 'gru'), Gs{s} = Lc.gru; lc_gru(:, s) = Lc.lcgru; ent_gru(:, s) = Lc.entgru; end
            fprintf('    [ckpt] loaded %s\n', ck); continue;
        end
        [A2Cs{s}, ~, lc_dac(:, s), ent_dac(:, s), Bs{s}, ~, bestEp, valCurves{s}] = ...
            DeepA2C_Shared_v12(simTime, ep_deep, baseSeed + 200 + s, env);
        fprintf('    [Deep A2C v12] Finished in %7.1f s | Final CellTp = %5.2f Mbps | best-on-val ep %d\n', ...
                toc(t0), lc_dac(end, s), bestEp);
        % v9: lightweight online calibrators (UCB bandits over the same offsets)
        [Bg{s}, lc_bg(:, s)] = Bandit_v12(simTime, ep_deep, baseSeed + 400 + s, env, 'global');
        [Bd{s}, lc_bd(:, s)] = Bandit_v12(simTime, ep_deep, baseSeed + 600 + s, env, 'delay');
        fprintf('    [Bandits] global arm %+d | delay-class arms %s\n', Bg{s}.arm, mat2str(Bd{s}.arm));
        if targMode
            % P1: contextual bandit over targets (replaces the delay-class
            % offset bandit as a comparator in target-mode cases).
            [Bt{s}, lc_bt(:, s)] = Bandit_v12(simTime, ep_deep, baseSeed + 800 + s, env, 'delay', 'target');
            fprintf('    [Target bandit] delay-class arms %s\n', mat2str(Bt{s}.arm));
        end
        if trainPPO
            t1 = tic;
            [Ps{s}, ~, lc_ppo(:, s), ent_ppo(:, s)] = DeepPPO_Shared_v12(simTime, epDeepPPO, baseSeed + 1000 + s, env);
            fprintf('    [Deep PPO v12] Finished in %7.1f s | Final CellTp = %5.2f Mbps\n', toc(t1), lc_ppo(end, s));
        end
        if trainGRU
            t2 = tic;
            [Gs{s}, ~, lc_gru(:, s), ent_gru(:, s)] = DeepGRU_Shared_v12(simTime, epDeepGRU, baseSeed + 1200 + s, env);
            fprintf('    [Deep GRU v12] Finished in %7.1f s | Final CellTp = %5.2f Mbps\n', toc(t2), lc_gru(end, s));
        end
        if ~exist(fileparts(ck), 'dir'), mkdir(fileparts(ck)); end
        S = struct('a2c', A2Cs{s}, 'abest', Bs{s}, 'valc', valCurves{s}, 'lc', lc_dac(:, s), 'ent', ent_dac(:, s), ...
                   'bg', Bg{s}, 'lbg', lc_bg(:, s), 'bd', Bd{s}, 'lbd', lc_bd(:, s));
        if targMode, S.bt = Bt{s}; S.lbt = lc_bt(:, s); end
        if trainPPO, S.ppo = Ps{s}; S.lcppo = lc_ppo(:, s); S.entppo = ent_ppo(:, s); end
        if trainGRU, S.gru = Gs{s}; S.lcgru = lc_gru(:, s); S.entgru = ent_gru(:, s); end
        save(ck, '-struct', 'S');
    end

    % -------------------------------------------------------------
    % Phase 2: Held-Out Trace Generation (N >= 100 Traces)
    % -------------------------------------------------------------
    fprintf('\nPHASE 2 -- Evaluation on %d Held-Out Traces\n', n_eval);
    traces = struct('SINR', [], 'obsS', [], 'meta', []);
    traces(n_eval).SINR = [];
    for j = 1:n_eval
        rng(traceSeedBase + j);
        [Strue, ~, meta] = generateChannel_v12(simTime, env);
        obsS = cqiFeedback_v12(Strue, env, meta.delays);
        meta.trace_id = j;
        rng(crnSeedBase + j); traces(j).U = rand(simTime, env.N);   % T2: CRN draws (default = v9/v11 behaviour)
        traces(j).SINR = Strue;
        traces(j).obsS = obsS;
        traces(j).meta = meta;
    end

    saveTag       = g('save_tag', 'headline');

    % v12 comparator set: Warm-OLLA / Fixed-Online replaced by the stronger
    % tuned-target OLLA and the same-information context table.
    % P0.4: scheme 8 = "last" checkpoint (headline, autonomous); 8b = the
    % checkpoint with the best score on validation traces (env.a2c.val_every).
    % With val_every = 0 (default), 8b falls back to the same ("last")
    % checkpoint, so the two rows are identical until validation is enabled.
    % Scheme list built dynamically: polSrc{k} says which policy cell array
    % (if any) evalPolicy_v12 needs for scheme k, so the eval loop and the
    % RL-scheme exclusion (cmpK, ACT histogram) never hardcode indices.
    schemes = {'Baseline', 'OLLA', 'OLLA (tuned target)', 'Multi-OLLA', 'Fixed', 'FixedPU (Oracle)', 'Context table'};
    ptypes  = {'baseline', 'olla', 'olla_tuned', 'multi_olla', 'fixed', 'fixed_class', 'ctxtab'};
    polSrc  = {'', '', '', '', '', '', ''};
    detK = 7; % Schemes 1 to 7 are deterministic across seeds

    schemes(end+1) = {'Deep A2C v12'};               ptypes(end+1) = {'a2c_v12'}; polSrc(end+1) = {'A2C'};
    schemes(end+1) = {'Deep A2C v12 (best-on-val)'};  ptypes(end+1) = {'a2c_v12'}; polSrc(end+1) = {'A2Cbest'};
    if trainPPO
        % P2: PPO trained and reported alongside A2C ("keep A2C for comparison").
        schemes(end+1) = {'Deep PPO v12'}; ptypes(end+1) = {'a2c_v12'}; polSrc(end+1) = {'PPO'};
    end
    if trainGRU
        % P4: GRU recurrent policy, its own eval ptype (stateful hand-coded
        % GRU step, see evalPolicy_v12).
        schemes(end+1) = {'Deep GRU v12'}; ptypes(end+1) = {'gru_v12'}; polSrc(end+1) = {'GRU'};
    end
    if targMode
        % P1: the per-class tuned target and the contextual target bandit
        % replace the delay-class offset bandit as same-information
        % comparators; the global offset bandit is kept for continuity.
        schemes(end+1) = {'Per-class tuned target'};                   ptypes(end+1) = {'olla_target_class'}; polSrc(end+1) = {''};
        schemes(end+1) = {'Bandit over targets (delay class)'};        ptypes(end+1) = {'bandit_target'};     polSrc(end+1) = {'BanditTarget'};
        schemes(end+1) = {'Bandit (global)'};                          ptypes(end+1) = {'bandit'};            polSrc(end+1) = {'BanditG'};
    else
        schemes(end+1) = {'Bandit (global)'};       ptypes(end+1) = {'bandit'}; polSrc(end+1) = {'BanditG'};
        schemes(end+1) = {'Bandit (delay class)'};  ptypes(end+1) = {'bandit'}; polSrc(end+1) = {'BanditD'};
    end
    K = numel(schemes);
    rlK = find(strcmp(polSrc, 'A2C') | strcmp(polSrc, 'A2Cbest') | strcmp(polSrc, 'PPO') | strcmp(polSrc, 'GRU'));

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
        if targMode, nAct = numel(env.target_set); else, nAct = numel(env.actions); end
        M = init_metrics_v12(K, n_seeds, n_eval, nAct);
        fprintf('\n--- Evaluating Scheduler: %s ---\n', upper(envE.scheduler));
        txtReport = [txtReport sprintf('---- SCHEDULER: %s ----\n', upper(envE.scheduler))];

        for j = 1:n_eval
            mt = traces(j).meta;
            for k = 1:K
                if k <= detK, ns = 1; else, ns = n_seeds; end
                for s = 1:ns
                    pol = [];
                    switch polSrc{k}
                        case 'A2C',          pol = A2Cs{s};
                        case 'A2Cbest',      pol = Bs{s};
                        case 'PPO',          pol = Ps{s};
                        case 'GRU',          pol = Gs{s};
                        case 'BanditTarget', pol = Bt{s};
                        case 'BanditG',      pol = Bg{s};
                        case 'BanditD',      pol = Bd{s};
                        % '' (e.g. 'olla_target_class') -- deterministic, no policy needed
                    end
                    rng(77000 + 100*j + 10*k + s);
                    [tp, bl, ce, act, inf] = evalPolicy_v12(ptypes{k}, pol, ...
                                                 traces(j).SINR, traces(j).obsS, envE, mt, traces(j).U);

                    b0 = min(env.burn_in, size(tp, 1) - 1);
                    tpB = tp(b0+1:end, :);
                    blB = bl(b0+1:end, :);
                    ceB = ce(b0+1:end, :);
                    bu  = mt.burst(b0+1:end);
                    pu  = mean(tpB, 1);

                    % P0.5: action histogram of the greedy policy (RL
                    % schemes only -- other schemes don't vary 'act').
                    if any(k == rlK)
                        actB = act(b0+1:end, :);
                        M.act_hist{k} = M.act_hist{k} + accumarray(actB(:), 1, [nAct, 1])';
                    end

                    M.cell_tp{k}(s, j) = sum(pu);
                    [~, ~, M.primary{k}(s, j)] = userMetric_v12(env, tp, inf, b0);
                    M.ontime{k}(s, j) = sum(inf.okU) / max(sum(inf.resU), 1);
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
            mean_bl = metricMean_v12(M.bler{k},     k, detK);
            mean_ed = metricMean_v12(M.edge_tp{k},  k, detK);
            mean_jn = metricMean_v12(M.jain{k},     k, detK);
            mean_bu = metricMean_v12(M.tp_burst{k}, k, detK);
            mean_ca = metricMean_v12(M.tp_calm{k},  k, detK);

            row = sprintf('  %-20s | %5.2f +/- %4.2f   | %5.3f  | %5.2f   | %5.3f  | %4.2f / %4.2f Mbps\n', ...
                          schemes{k}, mean_tp, ci_tp, mean_bl, mean_ed, mean_jn, mean_bu, mean_ca);
            fprintf('%s', row);
            txtReport = [txtReport row];
        end
        eq_sep = sprintf('========================================================================================\n\n');
        fprintf('%s', eq_sep);
        txtReport = [txtReport eq_sep];

        % Statistical testing: each "main" RL scheme (A2C last; PPO, if
        % trained) vs every non-RL comparator. "(best-on-val)" gets its own
        % row in the table above but no separate stats block (it is
        % identical to the "last" row unless env.a2c.val_every > 0).
        cmpK = setdiff(1:K, rlK);  % exclude every RL scheme from the comparator set
        rlMain = rlK(~contains(schemes(rlK), 'best-on-val'));
        for kr = rlMain
            tp_rl = tp_all{kr};
            st_hdr = sprintf('STATISTICAL SIGNIFICANCE & TOST EQUIVALENCE TESTING (%s vs. Comparators):\n', schemes{kr});
            fprintf('%s', st_hdr);
            txtReport = [txtReport st_hdr];

            % Raw paired Wilcoxon p-values, then Holm-Bonferroni adjustment
            % (AUDIT FIX: the design plan and reports state Holm correction,
            % but only raw p-values were ever reported).
            p_raw = nan(1, K);
            for k = cmpK
                if exist('signrank', 'file') == 2
                    p_raw(k) = signrank(tp_rl, tp_all{k});
                end
            end
            p_holm = holmAdjust_v12(p_raw);

            for k = cmpK
                tp_comp = tp_all{k};
                delta = tp_rl - tp_comp;
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
        end
        M_all = [M_all, M]; %#ok<AGROW>
    end

    % Package results
    % T2 (PLAN_v12_replication.md): record the seed bases so the
    % replication is checkable from the CONFIG/V12ENV log line alone.
    env.crn_seed_base   = crnSeedBase;
    env.trace_seed_base = traceSeedBase;
    env.base_seed       = baseSeed;
    policies = struct('A2C', {A2Cs}, 'A2Cbest', {Bs}, 'Bandit', {Bg}, 'BanditD', {Bd});
    bandit_curves = struct('global', lc_bg, 'delay', lc_bd);
    if targMode, policies.BanditTarget = Bt; bandit_curves.target = lc_bt; end
    if trainPPO, policies.PPO = Ps; end
    if trainGRU, policies.GRU = Gs; end
    results = struct('env', env, 'schemes', {schemes}, 'metrics', M_all, ...
                     'eval_schedulers', {eval_scheds}, ...
                     'policies', policies, ...
                     'learning_curves', lc_dac, 'entropy_curves', ent_dac, 'val_curves', {valCurves}, ...
                     'ppo_curves', struct('learning', lc_ppo, 'entropy', ent_ppo), ...
                     'gru_curves', struct('learning', lc_gru, 'entropy', ent_gru), ...
                     'bandit_curves', bandit_curves);

    outDir = fullfile(here, 'Dataset');
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    matFile = fullfile(outDir, sprintf('results_v12_%s.mat', saveTag));
    txtFile = fullfile(outDir, sprintf('results_v12_%s.txt', saveTag));
    save(matFile, 'results', '-v7.3');

    fid = fopen(txtFile, 'w');
    if fid ~= -1
        fwrite(fid, txtReport);
        fclose(fid);
    end
    fprintf('\nResults successfully saved to:\n  MAT: %s\n  TXT: %s\n', matFile, txtFile);
end

function M = init_metrics_v12(K, n_seeds, n_eval, nA)
    % AUDIT FIX: pre-allocate with NaN, not zeros. Deterministic schemes only
    % fill row 1, and zero-filled rows were being averaged into their stats.
    Z = nan(n_seeds, n_eval);
    M.cell_tp  = repmat({Z}, 1, K);
    M.primary  = repmat({Z}, 1, K);
    M.ontime   = repmat({Z}, 1, K);
    M.edge_tp  = repmat({Z}, 1, K);
    M.bler     = repmat({Z}, 1, K);
    M.jain     = repmat({Z}, 1, K);
    M.cqie     = repmat({Z}, 1, K);
    M.tp_burst = repmat({Z}, 1, K);
    M.tp_calm  = repmat({Z}, 1, K);
    if nargin < 4, nA = 0; end
    M.act_hist = repmat({zeros(1, nA)}, 1, K);  % P0.5: greedy-policy action histogram (A2C schemes)
end

function val = get_def(s, field, defaultVal)
    if isfield(s, field) && ~isempty(s.(field))
        val = s.(field);
    else
        val = defaultVal;
    end
end
