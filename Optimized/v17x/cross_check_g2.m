function cross_check_g2()
    addpath('Optimized/v17');
    addpath('Optimized/v17/headroom');
    addpath('Optimized/v17x');
    addpath('Optimized/v17x/g6');
    addpath('Optimized/v17x/nr1');
    v17_setup;

    % Load calibrations
    c_g2 = load('Optimized/v17x/Dataset/ckpt/g10/calib_single_G2_hi_d10.mat');
    env_cal = c_g2.out.env;
    env_cal.base_rule_kind = 'fixed';
    env_cal.base_rule_name = 'Fixed';
    env_cal.base_rule_force = 'fixed';
    env_cal.fixed_offset = c_g2.out.fixed_offset;
    b0_cal = min(env_cal.burn_in, base.simTime - 1);

    % Load r5 eval env (which had pkt_bits=16000)
    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile('Optimized/v17/Dataset', sprintf('results_v17_%s.mat', tag)));
    R_M1 = data.results; env_M1 = R_M1.env;
    env_r5 = env_M1;
    env_r5.pkt_bits = 16000;
    env_r5.pkt_deadline = 10;
    env_r5.base_rule_kind = 'fixed';
    env_r5.base_rule_name = 'Fixed';
    env_r5.base_rule_force = 'fixed';
    env_r5.fixed_offset = c_g2.out.fixed_offset;
    b0_r5 = min(env_r5.burn_in, o.simTime - 1);

    fprintf('env_cal (stage_nr_g10) pkt_bits = %d\n', env_cal.pkt_bits);
    fprintf('env_r5  (stage_r5_seeds) pkt_bits = %d\n', env_r5.pkt_bits);

    % Load stored NR-G10 policies (seeds 1..5)
    pols_1_5 = cell(1, 5);
    for s = 1:5
        p = load(sprintf('Optimized/v17x/Dataset/ckpt/nr_g10/train_seed_G2_hi_d10_%d.mat', s));
        pols_1_5{s} = p.out.a2c;
    end

    % Load r5 fresh policies (seeds 6..10)
    pols_6_10 = cell(1, 5);
    for s = 6:10
        p = load(sprintf('Optimized/v17x/Dataset/ckpt/r5_seeds/train_G2_hi_d10_%d.mat', s));
        pols_6_10{s-5} = p.out.a2c;
    end

    n_eval = 500;

    % Pre-generate traces for both environments
    fprintf('Pre-generating %d traces for env_r5 (16k) and env_cal (14k)...\n', n_eval);
    traces_r5 = cell(1, n_eval);
    traces_cal = cell(1, n_eval);
    for j = 1:n_eval
        % r5 traces
        rng(720000 + j); [S, ~, meta] = generateChannel_v17(o.simTime, env_r5);
        obsS = cqiFeedback_v17(S, env_r5, meta.delays);
        meta.trace_id = j;
        rng(730000 + j); U = rand(o.simTime, env_r5.N);
        traces_r5{j} = struct('S', S, 'obsS', obsS, 'meta', meta, 'U', U);

        % cal traces
        rng(720000 + j); [S, ~, meta] = generateChannel_v17(o.simTime, env_cal);
        obsS = cqiFeedback_v17(S, env_cal, meta.delays);
        meta.trace_id = j;
        rng(730000 + j); U = rand(o.simTime, env_cal.N);
        traces_cal{j} = struct('S', S, 'obsS', obsS, 'meta', meta, 'U', U);
    end

    % (a) Evaluate stored seeds 1..5 through r5 path (env_r5, pkt_bits=16000)
    fprintf('\n--- (a) Stored seeds 1-5 through R5 evaluation path (pkt_bits=16000) ---\n');
    vals_1_5_r5 = zeros(5, n_eval);
    for s = 1:5
        pol = pols_1_5{s};
        for j = 1:n_eval
            tr = traces_r5{j};
            rng(720000 + 100*j + 10*8 + s);
            [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('a2c_v17', pol, tr.S, tr.obsS, env_r5, tr.meta, tr.U);
            [~, ~, vals_1_5_r5(s, j)] = userMetric_v17(env_r5, tp, inf, b0_r5);
        end
        fprintf('  Stored Seed %d on R5 env (16k): %.4f\n', s, mean(vals_1_5_r5(s, :)));
    end
    fprintf('  Mean Stored Seeds 1-5 on R5 env (16k): %.4f\n', mean(mean(vals_1_5_r5)));

    % (b) Evaluate r5 fresh seeds 6..10 through original stage_nr_g10 evaluator (env_cal, pkt_bits=14000)
    fprintf('\n--- (b) R5 fresh seeds 6-10 through original stage_nr_g10 evaluator (pkt_bits=14000) ---\n');
    vals_6_10_cal = zeros(5, n_eval);
    for s = 1:5
        pol = pols_6_10{s};
        s_idx = 5 + s;
        for j = 1:n_eval
            tr = traces_cal{j};
            rng(77000 + 100*j + 10*8 + s_idx);
            [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('a2c_v17', pol, tr.S, tr.obsS, env_cal, tr.meta, tr.U);
            [~, ~, vals_6_10_cal(s, j)] = userMetric_v17(env_cal, tp, inf, b0_cal);
        end
        fprintf('  Fresh Seed %d on stage_nr_g10 env (14k): %.4f\n', s_idx, mean(vals_6_10_cal(s, :)));
    end
    fprintf('  Mean Fresh Seeds 6-10 on stage_nr_g10 env (14k): %.4f\n', mean(mean(vals_6_10_cal)));

    % Save results
    res = struct('vals_1_5_r5', vals_1_5_r5, 'vals_6_10_cal', vals_6_10_cal, ...
                 'mean_1_5_r5', mean(mean(vals_1_5_r5)), 'mean_6_10_cal', mean(mean(vals_6_10_cal)));
    save('Optimized/v17x/Dataset/g2_cross_check_results.mat', 'res');
    fprintf('\nSaved to Optimized/v17x/Dataset/g2_cross_check_results.mat\n');
end
