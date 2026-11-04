function fill_stats_v9(matFile, tag, fid)
% fill_stats_v9  Write per-scheme metrics and A2C-vs-comparator statistics
% (Wilcoxon, Holm, 90% CI, TOST at +/-2% relative and +/-0.10 Mbps).
    L = load(matFile, 'results'); r = L.results; M = r.metrics(1);
    K = numel(r.schemes); detK = 7;
    n_eval = size(M.cell_tp{1}, 2);
    tp = cell(1, K);
    for k = 1:K
        if k <= detK, tp{k} = M.cell_tp{k}(1, :); else, tp{k} = mean(M.cell_tp{k}, 1, 'omitnan'); end
    end
    fprintf(fid, '\n### POINT %s  (%s)\n', tag, datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    fprintf(fid, 'CONFIG|%s|n_eval=%d|n_seeds=%d|tier=%s|episodes=%d|olla_warm_ttis=%d|actions=%s|train_sched=%s\n', tag, n_eval, ...
            size(M.cell_tp{8}, 1), r.env.state_tier, size(r.learning_curves, 1), r.env.olla_warm_ttis, mat2str(r.env.actions), mat2str(r.env.train_sched_weights));
    fprintf(fid, 'CALIB|%s|fixed_offset=%d|class_tab=%s\n', tag, r.env.fixed_offset, mat2str(r.env.fixed_class_tab));
    if isfield(r.env, 'mob_kappa'), fprintf(fid, 'V9ENV|%s|mob_kappa=%g|crn=%d|train_warm=%d|calib_warm=%d|sched=%s|burst_dB=%g|hetero=%g|sched_on_ref=%d|lambda=[%g %g]\n', tag, r.env.mob_kappa, r.env.crn, r.env.train_warm_ttis, r.env.calib_warm, r.env.calib_sched, r.env.burst_IM_dB, r.env.hetero, isfield(r.env,'sched_on_ref') && r.env.sched_on_ref, r.env.lambda_retx, r.env.lambda_drop); end
    for k = 1:K
        fprintf(fid, 'SCHEME|%s|%s|tp=%.4f|ci95=%.4f|bler1=%.4f|edge=%.4f|jain=%.4f|burst=%.4f|calm=%.4f\n', ...
            tag, r.schemes{k}, mean(tp{k}), 1.96*std(tp{k})/sqrt(n_eval), ...
            metricMean_v9(M.bler{k}, k, detK), metricMean_v9(M.edge_tp{k}, k, detK), ...
            metricMean_v9(M.jain{k}, k, detK), metricMean_v9(M.tp_burst{k}, k, detK), ...
            metricMean_v9(M.tp_calm{k}, k, detK));
    end
    seedMeans = mean(M.cell_tp{8}, 2, 'omitnan')';
    fprintf(fid, 'SEEDS|%s|a2c_seed_means=%s|vsFixedPU_pct=%s\n', tag, mat2str(round(seedMeans, 4)), ...
            mat2str(round(100*(seedMeans - mean(tp{7}))/mean(tp{7}), 2)));
    lc = r.learning_curves; ec = r.entropy_curves;
    fprintf(fid, 'TRAIN|%s|final_train_tp_mean=%.4f|final_entropy_mean=%.4f|max_entropy=%.4f\n', tag, ...
            mean(lc(end, :)), mean(ec(end, :)), log(numel(r.env.actions)));
    cmpK = [1:7, 9:K];
    p_raw = nan(1, K);
    for k = cmpK, p_raw(k) = signrank(tp{8}, tp{k}); end
    p_h = holmAdjust_v9(p_raw);
    for k = cmpK
        d = tp{8} - tp{k}; md = mean(d); se = std(d)/sqrt(n_eval); base = mean(tp{k});
        ci90 = md + [-1 1]*tinv(0.95, n_eval-1)*se;
        m2 = 0.02*base;
        p2 = max(1 - tcdf((md + m2)/se, n_eval-1), 1 - tcdf((m2 - md)/se, n_eval-1));
        m1 = 0.10;
        p1 = max(1 - tcdf((md + m1)/se, n_eval-1), 1 - tcdf((m1 - md)/se, n_eval-1));
        fprintf(fid, 'CMP|%s|A2C vs %s|diff=%.4f|pct=%.2f|ci90pct=[%.2f %.2f]|wilcoxon=%.3g|holm=%.3g|tost2pct=%.3g|tost010=%.3g\n', ...
            tag, r.schemes{k}, md, 100*md/base, 100*ci90(1)/base, 100*ci90(2)/base, p_raw(k), p_h(k), p2, p1);
    end
    % v9: bandit calibrators against the offline references (not Holm-corrected)
    if K >= 10 && isfield(r.policies, 'Bandit')
        for kb = 9:K
            for kr = [2 5 7]
                d = tp{kb} - tp{kr}; md = mean(d); se = std(d)/sqrt(n_eval); base = mean(tp{kr});
                ci90 = md + [-1 1]*tinv(0.95, n_eval-1)*se; m2 = 0.02*base;
                p2 = max(1 - tcdf((md + m2)/se, n_eval-1), 1 - tcdf((m2 - md)/se, n_eval-1));
                fprintf(fid, 'BCMP|%s|%s vs %s|pct=%.2f|ci90pct=[%.2f %.2f]|wilcoxon=%.3g|tost2pct=%.3g\n', ...
                    tag, r.schemes{kb}, r.schemes{kr}, 100*md/base, 100*ci90(1)/base, 100*ci90(2)/base, signrank(tp{kb}, tp{kr}), p2);
            end
        end
        armsG = cellfun(@(p) p.arm, r.policies.Bandit);
        armsD = cell2mat(cellfun(@(p) p.arm(:)', r.policies.BanditD, 'UniformOutput', false)');
        fprintf(fid, 'BARMS|%s|global=%s|delay_class=%s\n', tag, mat2str(armsG), mat2str(armsD));
    end
end
