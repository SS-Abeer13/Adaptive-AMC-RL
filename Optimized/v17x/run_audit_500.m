function res = run_audit_500()
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
    R_M1 = data.results; envFixed = R_M1.env;
    envFixed.base_rule_force = 'fixed';
    envFixed.fixed_offset = -2;
    [envFixed, ~] = selectBaseRule_v17n(envFixed, 2, o.simTime);
    b0 = min(envFixed.burn_in, o.simTime - 1);
    N = envFixed.N;
    simTime = o.simTime;
    n_traces = 500;

    % Load GBT models
    s_tr = load('Optimized/v17x/Dataset/ckpt/r1_gbt/gbt_trees.mat');
    gbt_models = s_tr.trees_export;

    % Load NR2 policies (10 seeds)
    nr2_pols = cell(1, 10);
    for s = 1:10
        s_dat = load(sprintf('Optimized/v17x/Dataset/ckpt/nr2/train_seed_%d.mat', s));
        nr2_pols{s} = s_dat.out.a2c;
    end

    % Load Context-joint table
    tables_file = 'Optimized/v17x/Dataset/cal500_tables.txt';
    e_ctxj = envFixed;
    e_ctxj.ctxj_tab = read_ctxj_from_tables(tables_file);

    % Start parallel pool with 6 workers
    p = gcp('nocreate');
    if isempty(p)
        try parpool(6); catch, parpool(2); end
    end

    schemes = {'Context-joint', 'NR2', 'gbt_res', 'gbt_full'};
    res = struct();

    for sc_i = 1:numel(schemes)
        sc = schemes{sc_i};
        fprintf('\n=== Evaluating %s on %d NR2 traces ===\n', sc, n_traces);
        t0 = tic;

        cell_ontime = zeros(1, n_traces);
        cell_goodput = zeros(1, n_traces);
        user_ot_cell = cell(1, n_traces);
        jain_traces = zeros(1, n_traces);
        bler1_cell = cell(1, n_traces);

        if strcmp(sc, 'Context-joint')
            parfor j = 1:n_traces
                tr_seed = 1000000 + j;
                crn_seed = 1010000 + j;
                rng(tr_seed); [Strue, ~, meta] = generateChannel_v17(simTime, e_ctxj);
                obsS = cqiFeedback_v17(Strue, e_ctxj, meta.delays);
                meta.trace_id = j;
                rng(crn_seed); U = rand(simTime, N);

                rng(1020000 + 100*j + 10*8 + 1);
                [tp, bler, ~, ~, inf] = evalPolicy_presub('ctxj', [], Strue, obsS, e_ctxj, meta, U);
                [num, den, cell_p] = userMetric_v17(e_ctxj, tp, inf, b0);
                cell_ontime(j) = cell_p;
                cell_goodput(j) = sum(mean(tp(b0+1:end, :), 1));

                u_ot = zeros(1, N);
                for u = 1:N
                    if den(u) > 0, u_ot(u) = num(u) / den(u); else, u_ot(u) = NaN; end
                end
                valid_u = u_ot(~isnan(u_ot));
                user_ot_cell{j} = valid_u;
                if sum(valid_u.^2) > 0
                    jain_traces(j) = (sum(valid_u)^2) / (length(valid_u) * sum(valid_u.^2));
                else
                    jain_traces(j) = 1.0;
                end
                bler_after = bler(b0+1:end, :);
                valid_b = bler_after(~isnan(bler_after));
                bler1_cell{j} = valid_b(:);
            end

        elseif strcmp(sc, 'NR2')
            % For NR2, evaluate across all 10 seeds and pool
            cell_ontime_seeds = zeros(10, n_traces);
            cell_gp_seeds = zeros(10, n_traces);
            jain_seeds = zeros(10, n_traces);
            user_ot_all = cell(10, n_traces);
            bler1_all = cell(10, n_traces);

            parfor j = 1:n_traces
                tr_seed = 1000000 + j;
                crn_seed = 1010000 + j;
                rng(tr_seed); [Strue, ~, meta] = generateChannel_v17(simTime, envFixed);
                obsS = cqiFeedback_v17(Strue, envFixed, meta.delays);
                meta.trace_id = j;
                rng(crn_seed); U = rand(simTime, N);

                for s = 1:10
                    rng(1020000 + 100*j + 10*8 + s);
                    [tp, bler, ~, ~, inf] = evalPolicy_presub('a2c_v17', nr2_pols{s}, Strue, obsS, envFixed, meta, U);
                    [num, den, cell_p] = userMetric_v17(envFixed, tp, inf, b0);
                    cell_ontime_seeds(s, j) = cell_p;
                    cell_gp_seeds(s, j) = sum(mean(tp(b0+1:end, :), 1));

                    u_ot = zeros(1, N);
                    for u = 1:N
                        if den(u) > 0, u_ot(u) = num(u) / den(u); else, u_ot(u) = NaN; end
                    end
                    valid_u = u_ot(~isnan(u_ot));
                    user_ot_all{s, j} = valid_u;
                    if sum(valid_u.^2) > 0
                        jain_seeds(s, j) = (sum(valid_u)^2) / (length(valid_u) * sum(valid_u.^2));
                    else
                        jain_seeds(s, j) = 1.0;
                    end
                    bler_after = bler(b0+1:end, :);
                    valid_b = bler_after(~isnan(bler_after));
                    bler1_all{s, j} = valid_b(:);
                end
            end
            cell_ontime = mean(cell_ontime_seeds, 1);
            cell_goodput = mean(cell_gp_seeds, 1);
            jain_traces = mean(jain_seeds, 1);
            user_ot_cell = user_ot_all(:)';
            bler1_cell = bler1_all(:)';

        else
            % GBT-res or GBT-full
            parfor j = 1:n_traces
                tr_seed = 1000000 + j;
                crn_seed = 1010000 + j;
                rng(tr_seed); [Strue, ~, meta] = generateChannel_v17(simTime, envFixed);
                obsS = cqiFeedback_v17(Strue, envFixed, meta.delays);
                meta.trace_id = j;
                rng(crn_seed); U = rand(simTime, N);

                rng(1020000 + 100*j + 10*8 + 1);
                [tp, bler, ~, ~, inf] = evalPolicy_presub(sc, gbt_models, Strue, obsS, envFixed, meta, U);
                [num, den, cell_p] = userMetric_v17(envFixed, tp, inf, b0);
                cell_ontime(j) = cell_p;
                cell_goodput(j) = sum(mean(tp(b0+1:end, :), 1));

                u_ot = zeros(1, N);
                for u = 1:N
                    if den(u) > 0, u_ot(u) = num(u) / den(u); else, u_ot(u) = NaN; end
                end
                valid_u = u_ot(~isnan(u_ot));
                user_ot_cell{j} = valid_u;
                if sum(valid_u.^2) > 0
                    jain_traces(j) = (sum(valid_u)^2) / (length(valid_u) * sum(valid_u.^2));
                else
                    jain_traces(j) = 1.0;
                end
                bler_after = bler(b0+1:end, :);
                valid_b = bler_after(~isnan(bler_after));
                bler1_cell{j} = valid_b(:);
            end
        end

        all_u = horzcat(user_ot_cell{:});
        jain_mean = mean(jain_traces);
        edge5 = prctile(all_u, 5);
        edge10 = prctile(all_u, 10);
        mean_ot = mean(cell_ontime);
        mean_gp = mean(cell_goodput);
        all_b = vertcat(bler1_cell{:});
        mean_bler1 = mean(all_b);

        fprintf('%s (%d traces in %.1f s):\n', sc, n_traces, toc(t0));
        fprintf('  On-time:  %.4f\n', mean_ot);
        fprintf('  Goodput:  %.2f Mbps\n', mean_gp);
        fprintf('  BLER1:    %.4f (%.2f%%)\n', mean_bler1, mean_bler1*100);
        fprintf('  Jain:     %.4f\n', jain_mean);
        fprintf('  Edge5:    %.4f\n', edge5);
        fprintf('  Edge10:   %.4f\n', edge10);

        res.(matlab.lang.makeValidName(sc)) = struct('ontime', mean_ot, 'goodput', mean_gp, ...
            'bler1', mean_bler1, 'jain', jain_mean, 'edge5', edge5, 'edge10', edge10);
    end

    save('Optimized/v17x/Dataset/audit_500_metrics.mat', 'res');
    fprintf('\nAll results saved to Optimized/v17x/Dataset/audit_500_metrics.mat\n');
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
