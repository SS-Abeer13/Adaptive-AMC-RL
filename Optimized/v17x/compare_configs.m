function compare_configs()
    addpath('Optimized/v17');
    addpath('Optimized/v17x');
    addpath('Optimized/v17x/nr1');
    addpath('Optimized/v17x/g6');
    v17_setup;

    % 1. Load G3 calib env
    c3 = load('Optimized/v17x/Dataset/ckpt/g10/calib_single_G3_lo_d18.mat');
    envG3_frozen = c3.out.env;
    fixed_off_G3_frozen = c3.out.fixed_offset;

    % Build G3 r5 eval env exactly as stage_r5_seeds.m does:
    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile('Optimized/v17/Dataset', sprintf('results_v17_%s.mat', tag)));
    R_M1 = data.results; env_M1 = R_M1.env;

    envN2 = env_M1;
    envN2.base_rule_force = 'fixed';
    envN2.fixed_offset = -2;
    [envN2, ~] = selectBaseRule_v17n(envN2, 2, o.simTime);
    envN2.scheme_name = 'Deep A2C v17 (non-oracle base)';

    % stage_r5_seeds.m lines 189-198:
    % g3_cfg = get_cell_cfg('G3_lo_d18', envN2);
    % where get_cell_cfg has:
    % cfg.env.pkt_bits = 8000; cfg.env.pkt_deadline = 18;
    g3_cfg_env = envN2;
    g3_cfg_env.pkt_bits = 8000;
    g3_cfg_env.pkt_deadline = 18;
    envG3_r5 = g3_cfg_env;
    envG3_r5.base_rule_kind = 'fixed';
    envG3_r5.base_rule_name = 'Fixed';
    envG3_r5.base_rule_force = 'fixed';
    envG3_r5.fixed_offset = fixed_off_G3_frozen;

    fprintf('=================================================================\n');
    fprintf('=== CONFIG CHECK 1: G3 Evaluation Env vs Frozen Calib Env ===\n');
    fprintf('=================================================================\n');
    check_fields = {'pkt_bits', 'pkt_deadline', 'pkt_period', 'lambda', 'load', 'base_rule_kind', 'fixed_offset', 'feat_tier', 'action_mode', 'N', 'total_RB', 'scheduler'};
    for i = 1:numel(check_fields)
        f = check_fields{i};
        v_frz = 'MISSING'; v_r5 = 'MISSING';
        if isfield(envG3_frozen, f), v_frz = mat2str(envG3_frozen.(f)); end
        if isfield(envG3_r5, f), v_r5 = mat2str(envG3_r5.(f)); end
        eq_str = 'MATCH';
        if ~isequal(v_frz, v_r5), eq_str = 'DIFF'; end
        fprintf('%-15s | Frozen: %-15s | R5: %-15s | %s\n', f, v_frz, v_r5, eq_str);
    end

    % Check all fields in envG3_frozen vs envG3_r5
    fn_all = unique([fieldnames(envG3_frozen); fieldnames(envG3_r5)]);
    diff_count_g3 = 0;
    for i = 1:numel(fn_all)
        f = fn_all{i};
        if isfield(envG3_frozen, f) && isfield(envG3_r5, f)
            if ~isequal(envG3_frozen.(f), envG3_r5.(f))
                diff_count_g3 = diff_count_g3 + 1;
                fprintf('  [G3 DIFF] %-20s: Frozen = %s, R5 = %s\n', f, mat2str(envG3_frozen.(f)), mat2str(envG3_r5.(f)));
            end
        else
            diff_count_g3 = diff_count_g3 + 1;
            fprintf('  [G3 FIELD DIFF] %-20s (one missing)\n', f);
        end
    end
    fprintf('Total G3 field differences: %d\n\n', diff_count_g3);

    % 2. NR2-20 vs Frozen NR2 env
    fprintf('=================================================================\n');
    fprintf('=== CONFIG CHECK 2: NR2-20 Evaluation Env vs Frozen NR2 Env ===\n');
    fprintf('=================================================================\n');
    % Frozen NR2 env:
    nr2_eval_file = 'Optimized/v17x/Dataset/ckpt/nr2/eval.mat';
    if exist(nr2_eval_file, 'file')
        st_nr2 = load(nr2_eval_file);
        disp('Fields in st_nr2.out:');
        disp(fieldnames(st_nr2.out));
        if isfield(st_nr2.out, 'env')
            envNR2_frozen = st_nr2.out.env;
        else
            % Load from results_v17_M1_dl_rtt8 or similar
            envNR2_frozen = envN2;
        end
    else
        envNR2_frozen = envN2;
    end
    envNR2_r5 = envN2; % in stage_r5_seeds.m line 146, Strue generated with envN2!

    for i = 1:numel(check_fields)
        f = check_fields{i};
        v_frz = 'MISSING'; v_r5 = 'MISSING';
        if isfield(envNR2_frozen, f), v_frz = mat2str(envNR2_frozen.(f)); end
        if isfield(envNR2_r5, f), v_r5 = mat2str(envNR2_r5.(f)); end
        eq_str = 'MATCH';
        if ~isequal(v_frz, v_r5), eq_str = 'DIFF'; end
        fprintf('%-15s | Frozen: %-15s | R5: %-15s | %s\n', f, v_frz, v_r5, eq_str);
    end

    fn_all_n2 = unique([fieldnames(envNR2_frozen); fieldnames(envNR2_r5)]);
    diff_count_n2 = 0;
    for i = 1:numel(fn_all_n2)
        f = fn_all_n2{i};
        if isfield(envNR2_frozen, f) && isfield(envNR2_r5, f)
            if ~isequal(envNR2_frozen.(f), envNR2_r5.(f))
                diff_count_n2 = diff_count_n2 + 1;
                fprintf('  [NR2 DIFF] %-20s: Frozen = %s, R5 = %s\n', f, mat2str(envNR2_frozen.(f)), mat2str(envNR2_r5.(f)));
            end
        else
            diff_count_n2 = diff_count_n2 + 1;
            fprintf('  [NR2 FIELD DIFF] %-20s (one missing)\n', f);
        end
    end
    fprintf('Total NR2-20 field differences: %d\n', diff_count_n2);
end
