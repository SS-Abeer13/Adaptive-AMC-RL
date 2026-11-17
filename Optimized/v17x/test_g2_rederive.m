function test_g2_rederive()
    addpath('Optimized/v17');
    addpath('Optimized/v17/headroom');
    addpath('Optimized/v17x');
    addpath('Optimized/v17x/g6');
    addpath('Optimized/v17x/nr1');
    v17_setup;

    % 1. Load calibration environment (14000 bits)
    c_g2 = load('Optimized/v17x/Dataset/ckpt/g10/calib_single_G2_hi_d10.mat');
    envCal = c_g2.out.env;
    envCal.base_rule_kind = 'fixed';
    envCal.base_rule_name = 'Fixed';
    envCal.base_rule_force = 'fixed';
    envCal.fixed_offset = c_g2.out.fixed_offset;
    assert(envCal.pkt_bits == 14000, 'envCal must have pkt_bits == 14000');
    assert(envCal.pkt_deadline == 10, 'envCal must have pkt_deadline == 10');
    assert(envCal.fixed_offset == -2, 'envCal must have fixed_offset == -2');
    T = base.simTime;
    b0 = min(envCal.burn_in, T - 1);

    % 2. Pre-generate 300 traces exactly per stage_nr_g10
    n_eval = 300;
    traces = struct('SINR', {}, 'obsS', {}, 'meta', {}, 'U', {});
    for j = 1:n_eval
        rng(720000 + j);
        [Strue, ~, meta] = generateChannel_v17(T, envCal);
        obsS = cqiFeedback_v17(Strue, envCal, meta.delays);
        meta.trace_id = j;
        rng(730000 + j); U = rand(T, envCal.N);
        traces(j).SINR = Strue; traces(j).obsS = obsS; traces(j).meta = meta; traces(j).U = U;
    end

    % 3. Check Seed 1 on first 20 traces vs stored eval_G2_hi_d10.mat
    p1 = load('Optimized/v17x/Dataset/ckpt/nr_g10/train_seed_G2_hi_d10_1.mat');
    pol1 = p1.out.a2c;
    s1_vals_20 = zeros(1, 20);
    for j = 1:20
        rng(77000 + 100*j + 10*8 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('a2c_v17', pol1, traces(j).SINR, traces(j).obsS, envCal, traces(j).meta, traces(j).U);
        [~, ~, s1_vals_20(j)] = userMetric_v17(envCal, tp, inf, b0);
    end

    st = load('Optimized/v17x/Dataset/ckpt/nr_g10/eval_G2_hi_d10.mat');
    st_s1_20 = st.out.rl_seeds(1, 1:20);
    diff20 = max(abs(s1_vals_20 - st_s1_20));
    fprintf('=== REPRO CHECK (Seed 1, first 20 traces) ===\n');
    fprintf('max abs diff = %.10e\n', diff20);
    assert(diff20 == 0, 'Seed 1 must reproduce stored values exactly!');

    % 4. Load fresh seeds 6..10
    pols_6_10 = cell(1, 5);
    for sp = 1:5
        s = 5 + sp;
        p = load(sprintf('Optimized/v17x/Dataset/ckpt/r5_seeds/train_G2_hi_d10_%d.mat', s));
        pols_6_10{sp} = p.out.a2c;
    end

    % 5. Derive under Formula A: rng(77000 + 100*j + 10*8 + s) with s = 6..10
    fprintf('\n=== FORMULA A: rng(77000 + 100*j + 10*8 + s), s = 6..10 ===\n');
    vals_A = zeros(5, n_eval);
    for sp = 1:5
        s = 5 + sp;
        pol = pols_6_10{sp};
        for j = 1:n_eval
            rng(77000 + 100*j + 10*8 + s);
            [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('a2c_v17', pol, traces(j).SINR, traces(j).obsS, envCal, traces(j).meta, traces(j).U);
            [~, ~, vals_A(sp, j)] = userMetric_v17(envCal, tp, inf, b0);
        end
        fprintf('  Seed %2d: mean = %.6f (first 5: %.6f, %.6f, %.6f, %.6f, %.6f)\n', ...
            s, mean(vals_A(sp, :)), vals_A(sp, 1:5));
    end
    fprintf('Formula A mean across seeds 6-10: %.6f\n', mean(mean(vals_A)));

    % 6. Derive under Formula B: rng(2140000 + 100*j + sp), sp = 1..5 (R_presub_prereg.md:132)
    fprintf('\n=== FORMULA B: rng(2140000 + 100*j + sp), sp = 1..5 ===\n');
    vals_B = zeros(5, n_eval);
    for sp = 1:5
        s = 5 + sp;
        pol = pols_6_10{sp};
        for j = 1:n_eval
            rng(2140000 + 100*j + sp);
            [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('a2c_v17', pol, traces(j).SINR, traces(j).obsS, envCal, traces(j).meta, traces(j).U);
            [~, ~, vals_B(sp, j)] = userMetric_v17(envCal, tp, inf, b0);
        end
        fprintf('  Seed %2d: mean = %.6f (first 5: %.6f, %.6f, %.6f, %.6f, %.6f)\n', ...
            s, mean(vals_B(sp, :)), vals_B(sp, 1:5));
    end
    fprintf('Formula B mean across seeds 6-10: %.6f\n', mean(mean(vals_B)));

    % Save results for inspection
    save('Optimized/v17x/Dataset/g2_rederive_results.mat', 'vals_A', 'vals_B', 'diff20');
    fprintf('\nDone.\n');
end
