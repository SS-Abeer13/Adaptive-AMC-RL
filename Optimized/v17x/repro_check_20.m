function repro_check_20()
    addpath('Optimized/v17');
    addpath('Optimized/v17/headroom');
    addpath('Optimized/v17x');
    addpath('Optimized/v17x/g6');
    addpath('Optimized/v17x/nr1');
    v17_setup;

    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile('Optimized/v17/Dataset', sprintf('results_v17_%s.mat', tag)));
    R_M1 = data.results; env_M1 = R_M1.env;
    envFixed = env_M1;
    envFixed.base_rule_force = 'fixed';
    envFixed.fixed_offset = -2;
    [envFixed, ~] = selectBaseRule_v17n(envFixed, 2, o.simTime);
    b0 = min(envFixed.burn_in, o.simTime - 1);

    % Load models
    s_tr = load('Optimized/v17x/Dataset/ckpt/r1_gbt/gbt_trees.mat');
    models = s_tr.trees_export;

    % Load stored evaluations
    st_r1 = load('Optimized/v17x/Dataset/ckpt/r1_gbt/eval_NR2.mat');
    stored_gbt_res  = st_r1.out.gbt_res(1:20);
    stored_gbt_full = st_r1.out.gbt_full(1:20);

    st_nr2 = load('Optimized/v17x/Dataset/ckpt/nr2/eval.mat');
    stored_nr2_s1   = st_nr2.out.nr2_seeds(1, 1:20);
    stored_ctxj     = st_nr2.out.cmp.ctxj500(1:20)';

    % Load NR2 policy seed 1
    s1 = load('Optimized/v17x/Dataset/ckpt/nr2/train_seed_1.mat');
    nr2_pol1 = s1.out.a2c;

    % Load Context-joint table
    tables_file = 'Optimized/v17x/Dataset/cal500_tables.txt';
    e_ctxj = envFixed;
    e_ctxj.ctxj_tab = read_ctxj_from_tables(tables_file);

    nT = 20;
    diff_nr2 = zeros(1, nT);
    diff_res = zeros(1, nT);
    diff_full = zeros(1, nT);
    diff_ctxj = zeros(1, nT);

    for j = 1:nT
        tr_seed = 1000000 + j;
        crn_seed = 1010000 + j;
        rng(tr_seed); [Strue, ~, meta] = generateChannel_v17(o.simTime, envFixed);
        obsS = cqiFeedback_v17(Strue, envFixed, meta.delays);
        meta.trace_id = j;
        rng(crn_seed); U = rand(o.simTime, envFixed.N);

        % 1. NR2 seed 1
        rng(1020000 + 100*j + 10*8 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_presub('a2c_v17', nr2_pol1, Strue, obsS, envFixed, meta, U);
        [~, ~, p] = userMetric_v17(envFixed, tp, inf, b0);
        diff_nr2(j) = abs(p - stored_nr2_s1(j));

        % 2. GBT-res
        rng(1020000 + 100*j + 10*8 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_presub('gbt_res', models, Strue, obsS, envFixed, meta, U);
        [~, ~, p] = userMetric_v17(envFixed, tp, inf, b0);
        diff_res(j) = abs(p - stored_gbt_res(j));

        % 3. GBT-full
        rng(1020000 + 100*j + 10*8 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_presub('gbt_full', models, Strue, obsS, envFixed, meta, U);
        [~, ~, p] = userMetric_v17(envFixed, tp, inf, b0);
        diff_full(j) = abs(p - stored_gbt_full(j));

        % 4. Context-joint-500
        rng(1020000 + 100*j + 10*8 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_presub('ctxj', [], Strue, obsS, e_ctxj, meta, U);
        [~, ~, p] = userMetric_v17(e_ctxj, tp, inf, b0);
        diff_ctxj(j) = abs(p - stored_ctxj(j));
    end

    fprintf('Reproduction on first 20 NR2 traces:\n');
    fprintf('  NR2 seed 1:       max abs diff = %.6e\n', max(diff_nr2));
    fprintf('  GBT-res:          max abs diff = %.6e\n', max(diff_res));
    fprintf('  GBT-full:         max abs diff = %.6e\n', max(diff_full));
    fprintf('  Context-joint:    max abs diff = %.6e\n', max(diff_ctxj));
end

function tab = read_ctxj_from_tables(fpath)
    tab = zeros(3, 2, 3, 2);
    lines = strsplit(fileread(fpath), sprintf('\n'));
    for i = 1:numel(lines)
        line = strtrim(lines{i});
        tok = regexp(line, 'cell\((\d+),(\d+),(\d+),(\d+)\) = ([+-]?\d+)', 'tokens', 'once');
        if ~isempty(tok)
            b = str2double(tok{1});
            d = str2double(tok{2});
            v = str2double(tok{3});
            u = str2double(tok{4}) + 1;
            off = str2double(tok{5});
            tab(b, d, v, u) = off;
        end
    end
end
