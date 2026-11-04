function stage_a1(ctx)
% stage_a1  Results by mobility regime (re-evaluation by speed class, prompt A1).
% Evaluates stored M1 policies (10 seeds), Context, Fixed, FixedPU on M1 traces.
% Saves per-user on-time counts (okU, resU), mean speed, and true delay to
% paper/a1/a1_peruser.mat and Dataset/a1_peruser.mat.
% Checks REPRO of cell_tp against stored metrics with maximum difference exactly 0.

    addpath(ctx.v17);
    v17_setup;
    
    ctx.unit('peruser', @() unit_peruser(ctx));
end

% =========================================================================
function out = unit_peruser(ctx)
    ctx.hbf('stage_a1: unit peruser start');
    
    r_file = fullfile(ctx.v17, 'Dataset', 'results_v17_M1_dl_rtt8.mat');
    if ~exist(r_file, 'file')
        error('v17x:a1:noM1', 'Cannot find M1 results at %s', r_file);
    end
    S = load(r_file);
    r = S.results;
    env = r.env;
    
    n_eval = 500;
    if isfield(ctx.cfg, 'smoke') && ctx.cfg.smoke
        n_eval = 2;
    end
    
    n_seeds = 10;
    if isfield(ctx.cfg, 'smoke') && ctx.cfg.smoke
        n_seeds = 2;
    end
    
    T = 200;
    if isfield(env, 'simTime'), T = env.simTime; end
    N = env.N;
    b0 = min(env.burn_in, T - 1);
    
    k_fixed = 5;
    k_fclass = 6;
    k_ctxtab = 7;
    k_a2c = 8;
    
    speeds = zeros(n_eval, N);
    delays = zeros(n_eval, N);
    
    okU_fixed = zeros(n_eval, N);
    resU_fixed = zeros(n_eval, N);
    
    okU_fclass = zeros(n_eval, N);
    resU_fclass = zeros(n_eval, N);
    
    okU_ctxtab = zeros(n_eval, N);
    resU_ctxtab = zeros(n_eval, N);
    
    okU_a2c = zeros(n_seeds, n_eval, N);
    resU_a2c = zeros(n_seeds, n_eval, N);
    
    max_repro_diff = 0;
    
    ctx.hbf(sprintf('Evaluating %d traces on 4 schemes (A2C %d seeds)', n_eval, n_seeds));
    
    for j = 1:n_eval
        if mod(j, 50) == 0 || j == n_eval
            ctx.hb(sprintf('a1 trace %d/%d (max diff = %e)', j, n_eval, max_repro_diff));
        end
        
        rng(500000 + j);
        [Strue, ~, meta] = generateChannel_v17(T, env);
        obsS = cqiFeedback_v17(Strue, env, meta.delays);
        meta.trace_id = j;
        rng(510000 + j); U = rand(T, N);
        
        speeds(j, :) = mean(meta.speeds, 1);
        delays(j, :) = meta.delays;
        
        % 1. Fixed
        rng(77000 + 100*j + 10*k_fixed + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17('fixed', [], Strue, obsS, env, meta, U);
        okU_fixed(j, :) = inf.okU;
        resU_fixed(j, :) = inf.resU;
        c_tp = sum(mean(tp(b0+1:end, :), 1));
        diff = abs(c_tp - r.metrics(1).cell_tp{k_fixed}(1, j));
        if diff > max_repro_diff, max_repro_diff = diff; end
        if diff ~= 0
            error('v17x:a1:repro', 'REPRO fail: Fixed trace %d diff = %e', j, diff);
        end
        
        % 2. FixedPU (Oracle)
        rng(77000 + 100*j + 10*k_fclass + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17('fixed_class', [], Strue, obsS, env, meta, U);
        okU_fclass(j, :) = inf.okU;
        resU_fclass(j, :) = inf.resU;
        c_tp = sum(mean(tp(b0+1:end, :), 1));
        diff = abs(c_tp - r.metrics(1).cell_tp{k_fclass}(1, j));
        if diff > max_repro_diff, max_repro_diff = diff; end
        if diff ~= 0
            error('v17x:a1:repro', 'REPRO fail: FixedPU trace %d diff = %e', j, diff);
        end
        
        % 3. Context table
        rng(77000 + 100*j + 10*k_ctxtab + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17('ctxtab', [], Strue, obsS, env, meta, U);
        okU_ctxtab(j, :) = inf.okU;
        resU_ctxtab(j, :) = inf.resU;
        c_tp = sum(mean(tp(b0+1:end, :), 1));
        diff = abs(c_tp - r.metrics(1).cell_tp{k_ctxtab}(1, j));
        if diff > max_repro_diff, max_repro_diff = diff; end
        if diff ~= 0
            error('v17x:a1:repro', 'REPRO fail: Context table trace %d diff = %e', j, diff);
        end
        
        % 4. Deep A2C v17 (10 seeds)
        for s = 1:n_seeds
            pol = r.policies.A2C{s};
            rng(77000 + 100*j + 10*k_a2c + s);
            [tp, ~, ~, ~, inf] = evalPolicy_v17('a2c_v17', pol, Strue, obsS, env, meta, U);
            okU_a2c(s, j, :) = inf.okU;
            resU_a2c(s, j, :) = inf.resU;
            c_tp = sum(mean(tp(b0+1:end, :), 1));
            diff = abs(c_tp - r.metrics(1).cell_tp{k_a2c}(s, j));
            if diff > max_repro_diff, max_repro_diff = diff; end
            if diff ~= 0
                error('v17x:a1:repro', 'REPRO fail: A2C seed %d trace %d diff = %e', s, j, diff);
            end
        end
    end
    
    ctx.hbf(sprintf('stage_a1: all REPRO checks passed cleanly (max_diff = %e)', max_repro_diff));
    
    % Save to a1_peruser.mat
    data = struct('speeds', speeds, ...
                  'delays', delays, ...
                  'okU_fixed', okU_fixed, ...
                  'resU_fixed', resU_fixed, ...
                  'okU_fixed_class', okU_fclass, ...
                  'resU_fixed_class', resU_fclass, ...
                  'okU_ctxtab', okU_ctxtab, ...
                  'resU_ctxtab', resU_ctxtab, ...
                  'okU_a2c', okU_a2c, ...
                  'resU_a2c', resU_a2c, ...
                  'n_eval', n_eval, ...
                  'n_seeds', n_seeds, ...
                  'max_repro_diff', max_repro_diff);
              
    out_ds = fullfile(ctx.outdir, 'a1_peruser.mat');
    save(out_ds, '-struct', 'data', '-v7.3');
    
    paper_a1_dir = fullfile(ctx.root, 'paper', 'a1');
    if ~exist(paper_a1_dir, 'dir')
        mkdir(paper_a1_dir);
    end
    save(fullfile(paper_a1_dir, 'a1_peruser.mat'), '-struct', 'data', '-v7.3');
    
    out = data;
end
