function results = runComparison_v17(opts)
% runComparison_v17  v8 Evaluation and benchmarking harness:
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
    crnSeedBase   = g('crn_seed_base', 50000);  % T2 (PLAN_v17_replication.md): default keeps v11 behaviour
    nCalib        = g('n_calib', 6);
    % P2 (IMPLEMENTATION_PLAN_v17.md): also train and report a PPO policy
    % ("Deep PPO v17") alongside A2C ("keep A2C for comparison"). Off by
    % default -- existing offset/target-mode A2C-only campaigns unaffected.
    trainPPO      = g('train_ppo', false);
    epDeepPPO     = g('ep_deep_ppo', ep_deep);
    % C2 (README_v17.md §3.3): PPO is pre-registered at a smaller seed count
    % than the primary A2C-resid scheme (5 vs 10 in the v17 core cases).
    % n_seeds_ppo defaults to n_seeds so existing campaigns that never set
    % it are unaffected; seeds beyond it are simply not trained (left NaN
    % in that scheme's metrics columns, which every aggregator below
    % already reads with 'omitnan').
    nSeedsPPO     = g('n_seeds_ppo', n_seeds);
    % C2 (README_v17.md §3.3/§4): train "Deep A2C v17 (offset)" -- the legacy
    % offset-action design, for continuity -- alongside the primary A2C-resid
    % scheme. Off by default (existing resid/offset/target-only campaigns
    % unaffected). Only meaningful when the primary action_mode is 'resid';
    % if it is already 'offset' this scheme would just duplicate "Deep A2C
    % v17" and is not trained.
    trainA2COffset = g('train_a2c_offset', false);
    epDeepA2CO     = g('ep_deep_a2c_offset', ep_deep);
    nSeedsA2CO     = g('n_seeds_a2c_offset', n_seeds);  % C2: 5 vs A2C-resid's 10, same NaN-padding scheme as PPO
    trainA2CResid800 = g('train_a2c_resid_800', false);
    epDeepA2CR800    = g('ep_deep_a2c_resid_800', 800);
    nSeedsA2CR800    = g('n_seeds_a2c_resid_800', n_seeds);
    % P4 (IMPLEMENTATION_PLAN_v17.md, scoped per README_v17.md): also train
    % and report a GRU recurrent policy ("Deep GRU v17"), offset action
    % space, A2C-style 16-step truncated-BPTT update. Off by default.
    trainGRU      = g('train_gru', false);
    epDeepGRU     = g('ep_deep_gru', ep_deep);

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', 'v7'));
    addpath(fullfile(here, '..', 'v5'));
    addpath(fullfile(here, '..', 'case2_3'));

    env = defaultEnv_v17(23, Nopt);
    % v17: every option whose name is an env field overrides that field
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

    % P1 (README_v17.md): action_mode = 'target' repurposes the A2C action
    % as an OLLA target-BLER arm; default 'offset' is the v9/v10/v17-P0 path.
    saveTagStr = g('save_tag', 'headline');
    targMode = isfield(env, 'action_mode') && strcmpi(env.action_mode, 'target');
    isResidPrimary = isfield(env, 'action_mode') && strcmpi(env.action_mode, 'resid');
    trainA2COffset = trainA2COffset && isResidPrimary;  % no-op when primary is already offset
    envOffset = env;
    if trainA2COffset, envOffset.action_mode = 'offset'; end

    % -------------------------------------------------------------
    % Phase 0: Calibrate Fixed-Offset Comparators
    % -------------------------------------------------------------
    update_heartbeat_v17(saveTagStr, 'Calibrating', 0, 0, 0);
    env = calibrateFixedClass_v17(env, nCalib, simTime);
    env = calibrateCtx_v17(env, env.n_calib_ctx, simTime);
    if targMode
        % P1 same-information comparator: per-class tuned target (the
        % target-mode analogue of FixedPU).
        env = calibrateTargetClass_v17(env, nCalib, simTime);
    end
    if isfield(env, 'action_mode') && strcmpi(env.action_mode, 'resid')
        [env, baseName] = selectBaseRule_v17(env, nCalib, simTime);
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
    Ps = cell(1, n_seeds);  % P2: Deep PPO v17 (trainPPO only)
    lc_ppo = zeros(epDeepPPO, n_seeds); ent_ppo = zeros(epDeepPPO, n_seeds);
    Ao = cell(1, n_seeds);  % C2: Deep A2C v17 (offset) (trainA2COffset only)
    lc_a2co = zeros(epDeepA2CO, n_seeds); ent_a2co = zeros(epDeepA2CO, n_seeds);
    Ar800 = cell(1, n_seeds); % C2: Deep A2C v17 (resid-800) (trainA2CResid800 only)
    lc_ar800 = zeros(epDeepA2CR800, n_seeds); ent_ar800 = zeros(epDeepA2CR800, n_seeds);
    Gs = cell(1, n_seeds);  % P4: Deep GRU v17 (trainGRU only)
    lc_gru = zeros(epDeepGRU, n_seeds); ent_gru = zeros(epDeepGRU, n_seeds);
    late_credit_fracs = zeros(1, n_seeds);

    useParfor = g('use_parfor', true);
    nWorkers  = g('n_workers', 2);
    if useParfor
        p = gcp('nocreate');
        if isempty(p)
            try
                parpool('local', nWorkers);
            catch
                useParfor = false;
            end
        elseif p.NumWorkers ~= nWorkers
            try
                delete(p);
                parpool('local', nWorkers);
            catch
                % Keep existing pool if recreate fails
            end
        end
    end
    M_workers = nWorkers * double(useParfor);
    saveTagStr = g('save_tag', 'headline');

    seedResults = cell(1, n_seeds);
    parfor (s = 1:n_seeds, M_workers)
        seedResults{s} = train_one_seed_v17(s, n_seeds, here, saveTagStr, env, envOffset, baseSeed, simTime, ep_deep, ...
                                            targMode, trainPPO, nSeedsPPO, epDeepPPO, ...
                                            trainA2COffset, nSeedsA2CO, epDeepA2CO, ...
                                            trainA2CResid800, nSeedsA2CR800, epDeepA2CR800, ...
                                            trainGRU, epDeepGRU);
    end

    % Unpack seed results
    for s = 1:n_seeds
        res = seedResults{s};
        A2Cs{s} = res.a2c;
        if isfield(res, 'abest'), Bs{s} = res.abest; else, Bs{s} = res.a2c; end
        if isfield(res, 'valc'), valCurves{s} = res.valc; end
        lc_dac(:, s) = res.lc; ent_dac(:, s) = res.ent;
        if isfield(res, 'late_credit_frac'), late_credit_fracs(s) = res.late_credit_frac; end
        Bg{s} = res.bg; lc_bg(:, s) = res.lbg;
        Bd{s} = res.bd; lc_bd(:, s) = res.lbd;
        if targMode && isfield(res, 'bt'), Bt{s} = res.bt; lc_bt(:, s) = res.lbt; end
        if trainPPO && s <= nSeedsPPO && isfield(res, 'ppo')
            Ps{s} = res.ppo; lc_ppo(:, s) = res.lcppo; ent_ppo(:, s) = res.entppo;
        end
        if trainA2COffset && s <= nSeedsA2CO && isfield(res, 'a2co')
            Ao{s} = res.a2co; lc_a2co(:, s) = res.lca2co; ent_a2co(:, s) = res.enta2co;
        end
        if trainA2CResid800 && s <= nSeedsA2CR800 && isfield(res, 'ar800')
            Ar800{s} = res.ar800; lc_ar800(:, s) = res.lcar800; ent_ar800(:, s) = res.entar800;
        end
        if trainGRU && isfield(res, 'gru')
            Gs{s} = res.gru; lc_gru(:, s) = res.lcgru; ent_gru(:, s) = res.entgru;
        end
    end

    % -------------------------------------------------------------
    % Phase 2: Held-Out Trace Generation (N >= 100 Traces)
    % -------------------------------------------------------------
    update_heartbeat_v17(saveTagStr, 'Evaluating', 0, 0, n_eval);
    fprintf('\nPHASE 2 -- Evaluation on %d Held-Out Traces\n', n_eval);
    traces = struct('SINR', [], 'obsS', [], 'meta', []);
    traces(n_eval).SINR = [];
    for j = 1:n_eval
        rng(traceSeedBase + j);
        [Strue, ~, meta] = generateChannel_v17(simTime, env);
        obsS = cqiFeedback_v17(Strue, env, meta.delays);
        meta.trace_id = j;
        rng(crnSeedBase + j); traces(j).U = rand(simTime, env.N);   % T2: CRN draws (default = v9/v11 behaviour)
        traces(j).SINR = Strue;
        traces(j).obsS = obsS;
        traces(j).meta = meta;
    end

    saveTag       = g('save_tag', 'headline');

    % v17 comparator set: Warm-OLLA / Fixed-Online replaced by the stronger
    % tuned-target OLLA and the same-information context table.
    % P0.4: scheme 8 = "last" checkpoint (headline, autonomous); 8b = the
    % checkpoint with the best score on validation traces (env.a2c.val_every).
    % With val_every = 0 (default), 8b falls back to the same ("last")
    % checkpoint, so the two rows are identical until validation is enabled.
    % Scheme list built dynamically: polSrc{k} says which policy cell array
    % (if any) evalPolicy_v17 needs for scheme k, so the eval loop and the
    % RL-scheme exclusion (cmpK, ACT histogram) never hardcode indices.
    schemes = {'Baseline', 'OLLA', 'OLLA (tuned target)', 'Multi-OLLA', 'Fixed', 'FixedPU (Oracle)', 'Context table'};
    ptypes  = {'baseline', 'olla', 'olla_tuned', 'multi_olla', 'fixed', 'fixed_class', 'ctxtab'};
    polSrc  = {'', '', '', '', '', '', ''};
    detK = 7; % Schemes 1 to 7 are deterministic across seeds

    schemes(end+1) = {'Deep A2C v17'};               ptypes(end+1) = {'a2c_v17'}; polSrc(end+1) = {'A2C'};
    schemes(end+1) = {'Deep A2C v17 (best-on-val)'};  ptypes(end+1) = {'a2c_v17'}; polSrc(end+1) = {'A2Cbest'};
    schemes(end+1) = {'Deep A2C v17 (ensemble)'};     ptypes(end+1) = {'a2c_ens'}; polSrc(end+1) = {'A2Cens'};
    if trainA2COffset
        % C2 (README_v17.md §3.3/§4): legacy offset-action A2C, trained
        % alongside the primary resid scheme, kept for continuity. Its own
        % ptype decodes offset actions unconditionally (see evalPolicy_v17.m
        % 'a2c_offset_v17', mirroring the 'ppo_v17' B2-fallback fix).
        schemes(end+1) = {'Deep A2C v17 (offset)'}; ptypes(end+1) = {'a2c_offset_v17'}; polSrc(end+1) = {'A2COffset'};
    end
    if trainA2CResid800
        schemes(end+1) = {'Deep A2C v17 (resid-800)'}; ptypes(end+1) = {'a2c_v17'}; polSrc(end+1) = {'A2CResid800'};
    end
    if trainPPO
        % P2: PPO trained and reported alongside A2C ("keep A2C for comparison").
        % B2 fallback fix (PLAN_v17.md): PPO decodes offset actions even
        % when the global action_mode is 'resid' (DeepPPO_Shared_v17 has no
        % resid support -- see README_v17 B2); it needs its own ptype so
        % evalPolicy_v17 doesn't index env.resid_actions with PPO's wider
        % offset-action index (see evalPolicy_v17.m's isPPOoffset note).
        schemes(end+1) = {'Deep PPO v17'}; ptypes(end+1) = {'ppo_v17'}; polSrc(end+1) = {'PPO'};
    end
    if trainGRU
        % P4: GRU recurrent policy, its own eval ptype (stateful hand-coded
        % GRU step, see evalPolicy_v17).
        schemes(end+1) = {'Deep GRU v17'}; ptypes(end+1) = {'gru_v17'}; polSrc(end+1) = {'GRU'};
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
    rlK = find(strcmp(polSrc, 'A2C') | strcmp(polSrc, 'A2Cbest') | strcmp(polSrc, 'A2Cens') | strcmp(polSrc, 'PPO') | strcmp(polSrc, 'GRU') | strcmp(polSrc, 'A2COffset') | strcmp(polSrc, 'A2CResid800'));

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
        if targMode
            nAct = numel(env.target_set);
        elseif isfield(env, 'action_mode') && strcmpi(env.action_mode, 'resid')
            nAct = numel(env.resid_actions);
            % B2 fallback fix (PLAN_v17.md): PPO decodes offset actions
            % (env.actions) even in a globally resid environment, so its
            % greedy-action indices can exceed numel(resid_actions). Widen
            % the shared act_hist bin count to fit both; A2C's own hist
            % simply leaves the extra high bins at zero.
            if trainPPO || trainA2COffset, nAct = max(nAct, numel(env.actions)); end
        else
            nAct = numel(env.actions);
        end
        M = init_metrics_v17(K, n_seeds, n_eval, nAct);
        fprintf('\n--- Evaluating Scheduler: %s ---\n', upper(envE.scheduler));
        txtReport = [txtReport sprintf('---- SCHEDULER: %s ----\n', upper(envE.scheduler))];

        for j = 1:n_eval
            mt = traces(j).meta;
            for k = 1:K
                % C2 (README_v17.md §3.3): PPO and A2C-offset are
                % pre-registered at a smaller seed count than A2C-resid
                % (nSeedsPPO/nSeedsA2CO vs n_seeds); evaluating only their
                % trained seeds leaves the remaining M.*{k} rows NaN, which
                % every aggregator (fill_stats_v17, analyze_v17_replication)
                % already reads with 'omitnan'.
                if k <= detK || strcmp(polSrc{k}, 'A2Cens')
                    ns = 1;
                elseif strcmp(polSrc{k}, 'PPO')
                    ns = nSeedsPPO;
                elseif strcmp(polSrc{k}, 'A2COffset')
                    ns = nSeedsA2CO;
                elseif strcmp(polSrc{k}, 'A2CResid800')
                    ns = nSeedsA2CR800;
                else
                    ns = n_seeds;
                end
                for s = 1:ns
                    pol = [];
                    switch polSrc{k}
                        case 'A2C',          pol = A2Cs{s};
                        case 'A2Cbest',      pol = Bs{s};
                        case 'A2Cens',       pol = A2Cs;
                        case 'PPO',          pol = Ps{s};
                        case 'A2COffset',    pol = Ao{s};
                        case 'A2CResid800',  pol = Ar800{s};
                        case 'GRU',          pol = Gs{s};
                        case 'BanditTarget', pol = Bt{s};
                        case 'BanditG',      pol = Bg{s};
                        case 'BanditD',      pol = Bd{s};
                        % '' (e.g. 'olla_target_class') -- deterministic, no policy needed
                    end
                    rng(77000 + 100*j + 10*k + s);
                    [tp, bl, ce, act, inf] = evalPolicy_v17(ptypes{k}, pol, ...
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
                    [num_m, den_m, M.primary{k}(s, j)] = userMetric_v17(env, tp, inf, b0);
                    pu_primary = num_m ./ max(den_m, 1);
                    M.ontime{k}(s, j) = sum(inf.okU) / max(sum(inf.resU), 1);
                    M.edge_tp{k}(s, j) = prctile(pu, 5); % 5th-percentile cell-edge throughput
                    ok = ~isnan(blB);
                    if any(ok(:)), M.bler{k}(s, j) = mean(blB(ok)); else, M.bler{k}(s, j) = NaN; end
                    M.jain{k}(s, j) = sum(pu_primary)^2 / (env.N * max(sum(pu_primary.^2), eps));
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
            if k <= detK || strcmp(polSrc{k}, 'A2Cens')
                tp_k = M.cell_tp{k}(1, :);
            else
                tp_k = mean(M.cell_tp{k}, 1, 'omitnan');
            end
            tp_all{k} = tp_k;

            mean_tp = mean(tp_k);
            ci_tp   = 1.96 * std(tp_k) / sqrt(n_eval);
            mean_bl = metricMean_v17(M.bler{k},     k, detK);
            mean_ed = metricMean_v17(M.edge_tp{k},  k, detK);
            mean_jn = metricMean_v17(M.jain{k},     k, detK);
            mean_bu = metricMean_v17(M.tp_burst{k}, k, detK);
            mean_ca = metricMean_v17(M.tp_calm{k},  k, detK);

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
            p_holm = holmAdjust_v17(p_raw);

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
    % T2 (PLAN_v17_replication.md): record the seed bases so the
    % replication is checkable from the CONFIG/V13ENV log line alone.
    env.crn_seed_base   = crnSeedBase;
    env.trace_seed_base = traceSeedBase;
    env.base_seed       = baseSeed;
    policies = struct('A2C', {A2Cs}, 'A2Cbest', {Bs}, 'Bandit', {Bg}, 'BanditD', {Bd});
    bandit_curves = struct('global', lc_bg, 'delay', lc_bd);
    if targMode, policies.BanditTarget = Bt; bandit_curves.target = lc_bt; end
    if trainPPO, policies.PPO = Ps; end
    if trainGRU, policies.GRU = Gs; end
    if trainA2COffset, policies.A2COffset = Ao; end
    results = struct('env', env, 'schemes', {schemes}, 'metrics', M_all, ...
                     'eval_schedulers', {eval_scheds}, ...
                     'policies', policies, ...
                     'learning_curves', lc_dac, 'entropy_curves', ent_dac, 'val_curves', {valCurves}, ...
                     'late_credit_fracs', late_credit_fracs, ...
                     'ppo_curves', struct('learning', lc_ppo, 'entropy', ent_ppo), ...
                     'gru_curves', struct('learning', lc_gru, 'entropy', ent_gru), ...
                     'a2c_offset_curves', struct('learning', lc_a2co, 'entropy', ent_a2co), ...
                     'bandit_curves', bandit_curves);

    outDir = fullfile(here, 'Dataset');
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    matFile = fullfile(outDir, sprintf('results_v17_%s.mat', saveTag));
    txtFile = fullfile(outDir, sprintf('results_v17_%s.txt', saveTag));
    save(matFile, 'results', '-v7.3');

    fid = fopen(txtFile, 'w');
    if fid ~= -1
        fwrite(fid, txtReport);
        fclose(fid);
    end
    fprintf('\nResults successfully saved to:\n  MAT: %s\n  TXT: %s\n', matFile, txtFile);
end

function M = init_metrics_v17(K, n_seeds, n_eval, nA)
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

function S = load_ckpt_helper(fn)
    S = load(fn);
end

function save_ckpt_helper(fn, S)
    if ~exist(fileparts(fn), 'dir'), mkdir(fileparts(fn)); end
    save(fn, '-struct', 'S');
end


function out = train_one_seed_v17(s, n_seeds, here, saveTagStr, env, envOffset, baseSeed, simTime, ep_deep, ...
                                  targMode, trainPPO, nSeedsPPO, epDeepPPO, ...
                                  trainA2COffset, nSeedsA2CO, epDeepA2CO, ...
                                  trainA2CResid800, nSeedsA2CR800, epDeepA2CR800, ...
                                  trainGRU, epDeepGRU)
    fprintf('  Seed %d/%d (%s)...\n', s, n_seeds, datestr(now, 'HH:MM:SS'));
    t0 = tic;
    ck = fullfile(here, 'Dataset', 'ckpt', sprintf('%s_seed%d.mat', saveTagStr, s));
    if exist(ck, 'file')
        try
            Lc = load(ck);
            out = Lc;
            fprintf('    [ckpt] loaded %s\n', ck);
            return;
        catch
        end
    end

    out = struct();
    envPrim = env;
    envPrim.case_tag = saveTagStr;
    envPrim.scheme_name = 'Deep A2C v17';
    envPrim.seed_idx = s;
    [out.a2c, ~, out.lc, out.ent, out.abest, ~, bestEp, out.valc, trainInfo] = ...
        DeepA2C_Shared_v17(simTime, ep_deep, baseSeed + 200 + s, envPrim);
    if isstruct(trainInfo) && isfield(trainInfo, 'late_credit_frac')
        out.late_credit_frac = trainInfo.late_credit_frac;
    else
        out.late_credit_frac = 0;
    end
    fprintf('    [Deep A2C v17] Finished in %7.1f s | Final CellTp = %5.2f Mbps | best-on-val ep %d\n', ...
            toc(t0), out.lc(end), bestEp);

    [out.bg, out.lbg] = Bandit_v17(simTime, ep_deep, baseSeed + 400 + s, env, 'global');
    [out.bd, out.lbd] = Bandit_v17(simTime, ep_deep, baseSeed + 600 + s, env, 'delay');
    fprintf('    [Bandits] global arm %+d | delay-class arms %s\n', out.bg.arm, mat2str(out.bd.arm));

    if targMode
        [out.bt, out.lbt] = Bandit_v17(simTime, ep_deep, baseSeed + 800 + s, env, 'delay', 'target');
        fprintf('    [Target bandit] delay-class arms %s\n', mat2str(out.bt.arm));
    end

    if trainPPO && s <= nSeedsPPO
        t1 = tic;
        [out.ppo, ~, out.lcppo, out.entppo] = DeepPPO_Shared_v17(simTime, epDeepPPO, baseSeed + 1000 + s, env);
        fprintf('    [Deep PPO v17] Finished in %7.1f s | Final CellTp = %5.2f Mbps\n', toc(t1), out.lcppo(end));
    end

    if trainA2COffset && s <= nSeedsA2CO
        t3 = tic;
        envOff = envOffset;
        envOff.case_tag = saveTagStr;
        envOff.scheme_name = 'Deep A2C v17 (offset)';
        envOff.seed_idx = s;
        [out.a2co, ~, out.lca2co, out.enta2co] = DeepA2C_Shared_v17(simTime, epDeepA2CO, baseSeed + 500 + s, envOff);
        fprintf('    [Deep A2C v17 (offset)] Finished in %7.1f s | Final CellTp = %5.2f Mbps\n', toc(t3), out.lca2co(end));
    end

    if trainA2CResid800 && s <= nSeedsA2CR800
        t4 = tic;
        envR800 = env;
        envR800.case_tag = saveTagStr;
        envR800.scheme_name = 'Deep A2C v17 (resid-800)';
        envR800.seed_idx = s;
        [out.ar800, ~, out.lcar800, out.entar800] = DeepA2C_Shared_v17(simTime, epDeepA2CR800, baseSeed + 300 + s, envR800);
        fprintf('    [Deep A2C v17 (resid-800)] Finished in %7.1f s | Final CellTp = %5.2f Mbps\n', toc(t4), out.lcar800(end));
    end

    if trainGRU
        t2 = tic;
        [out.gru, ~, out.lcgru, out.entgru] = DeepGRU_Shared_v17(simTime, epDeepGRU, baseSeed + 1200 + s, env);
        fprintf('    [Deep GRU v17] Finished in %7.1f s | Final CellTp = %5.2f Mbps\n', toc(t2), out.lcgru(end));
    end

    if ~exist(fileparts(ck), 'dir'), mkdir(fileparts(ck)); end
    save(ck, '-struct', 'out');
end
