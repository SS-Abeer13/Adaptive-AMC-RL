function out = audit_gbt_metrics(n_traces)
    if nargin < 1, n_traces = 500; end
    addpath('Optimized/v17');
    addpath('Optimized/v17/headroom');
    addpath('Optimized/v17x');
    addpath('Optimized/v17x/nr1');
    addpath('Optimized/v17x/g6');
    v17_setup;

    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile('Optimized/v17/Dataset', sprintf('results_v17_%s.mat', tag)));
    R_M1 = data.results; envFixed = R_M1.env;
    envFixed.base_rule_force = 'fixed';
    envFixed.fixed_offset = -2;
    [envFixed, ~] = selectBaseRule_v17n(envFixed, 2, o.simTime);

    s_tr = load('Optimized/v17x/Dataset/ckpt/r1_gbt/gbt_trees.mat');
    models = s_tr.trees_export;

    b0 = min(envFixed.burn_in, o.simTime - 1);
    N = envFixed.N;

    % Open parpool if not open
    p = gcp('nocreate');
    if isempty(p)
        try parpool(2); catch, end
    end

    schemes = {'gbt_res', 'gbt_full'};
    res = struct();

    for sc_idx = 1:numel(schemes)
        sc = schemes{sc_idx};
        fprintf('Evaluating %s on %d traces...\n', sc, n_traces);
        t0 = tic;

        cell_ontime = zeros(1, n_traces);
        cell_goodput = zeros(1, n_traces);
        user_ot_cell = cell(1, n_traces);
        jain_traces = zeros(1, n_traces);
        bler1_cell = cell(1, n_traces);
        acts_cell = cell(1, n_traces);

        simTime = o.simTime;

        parfor j = 1:n_traces
            tr_seed = 1000000 + j;
            crn_seed = 1010000 + j;
            rng(tr_seed); [Strue, ~, meta] = generateChannel_v17(simTime, envFixed);
            obsS = cqiFeedback_v17(Strue, envFixed, meta.delays);
            meta.trace_id = j;
            rng(crn_seed); U = rand(simTime, N);

            rng(1020000 + 100*j + 10*8 + 1);
            [tp, bler, ~, act, inf] = evalPolicy_presub(sc, models, Strue, obsS, envFixed, meta, U);

            % On-time & Goodput
            [num, den, cell_p] = userMetric_v17(envFixed, tp, inf, b0);
            cell_ontime(j) = cell_p;
            cell_goodput(j) = sum(mean(tp(b0+1:end, :), 1));

            % Per-user on-time
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

            % BLER on 1st transmissions after burn-in
            bler_after = bler(b0+1:end, :);
            valid_b = bler_after(~isnan(bler_after));
            bler1_cell{j} = valid_b(:);

            % Actions on scheduled new transmissions after burn-in
            sch = inf.sch_log;
            if ~isempty(sch)
                new_tx = sch(sch(:, 4) == 0, :);
                acts_cell{j} = new_tx(:, 2);
            else
                acts_cell{j} = [];
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
        all_a = vertcat(acts_cell{:});

        fprintf('\n%s (%d traces in %.1f s):\n', sc, n_traces, toc(t0));
        fprintf('  On-time: %.4f\n', mean_ot);
        fprintf('  Goodput: %.2f Mbps\n', mean_gp);
        fprintf('  BLER1: %.4f (%.2f%%)\n', mean_bler1, mean_bler1*100);
        fprintf('  Jain: %.4f\n', jain_mean);
        fprintf('  Edge5: %.4f\n', edge5);
        fprintf('  Edge10: %.4f\n', edge10);

        % Distribution of applied offsets (and delta relative to -2)
        u_acts = unique(all_a);
        fprintf('  Offset distribution (count = %d):\n', numel(all_a));
        dist_tbl = [];
        for ua = u_acts(:)'
            pct = mean(all_a == ua) * 100;
            d_rel = ua - (-2);
            fprintf('    offset %d (delta=%+d): %.2f%%\n', ua, d_rel, pct);
            dist_tbl = [dist_tbl; ua, d_rel, pct]; %#ok<AGROW>
        end

        res.(sc) = struct('ontime', mean_ot, 'goodput', mean_gp, 'bler1', mean_bler1, ...
            'jain', jain_mean, 'edge5', edge5, 'edge10', edge10, ...
            'dist_tbl', dist_tbl, 'cell_ontime', cell_ontime, ...
            'cell_goodput', cell_goodput, 'user_ontime', all_u, 'all_acts', all_a);
    end
    out = res;
    save('Optimized/v17x/Dataset/gbt_audit_metrics.mat', 'res');
    fprintf('\nSaved results to Optimized/v17x/Dataset/gbt_audit_metrics.mat\n');
end
