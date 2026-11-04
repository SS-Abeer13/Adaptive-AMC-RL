function pf = stage_a6_preflight(ctx)
% stage_a6_preflight  Preflight rate benchmark for A6 (PF timing demonstration).

    addpath(ctx.v17);
    v17_setup;
    ov = C.M3_gp_rtt8;
    o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    env = defaultEnv_v17(42, o.N);
    env.traffic = 'full';
    env.drain = true;
    env.useful_bits = true;
    env.reward_kind = 'oppcost';
    env.primary = 'goodput';
    env.fixed_offset = -1;
    env.olla_target = 0.10;
    env.olla_step_down = 0.01;
    env.pf_avg = 'scheduled';
    
    n_pf = 20;
    if isfield(ctx.cfg, 'smoke') && ctx.cfg.smoke
        n_pf = 2;
    end
    
    t0 = tic;
    b0 = min(env.burn_in, 199);
    for j = 1:n_pf
        rng(800000 + j, 'twister');
        [Strue, ~, meta] = generateChannel_v17(200, env);
        obsS = cqiFeedback_v17(Strue, env, meta.delays);
        meta.trace_id = j;
        rng(810000 + j, 'twister'); U = rand(200, env.N);
        
        [tp, ~, ~, ~, inf] = evalPolicy_v17('baseline', [], Strue, obsS, env, meta, U);
        userMetric_v17(env, tp, inf, b0);
    end
    dt = toc(t0);
    sec_per_unit = dt / n_pf;
    
    % Total evaluations: 6 cells * 3 schemes * 100 traces = 1800
    n_traces_tot = 100;
    if isfield(ctx.cfg, 'smoke') && ctx.cfg.smoke
        n_traces_tot = 2;
    end
    n_units_total = 6 * 3 * n_traces_tot;
    
    pf = struct('unit', 'eval', ...
                'sec_per_unit', sec_per_unit, ...
                'n_units_total', n_units_total, ...
                'note', sprintf('a6: 20-trace benchmark: %.4f s/eval (basis 0.095 s)', sec_per_unit));
end
