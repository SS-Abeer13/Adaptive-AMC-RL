function fill_sanity2_v9(matFile, tag, fid)
% fill_sanity2_v9  Random-action control and constant-offset landscape on the
% held-out traces of one campaign point (uses that point's env).
    L = load(matFile, 'results'); r = L.results; M = r.metrics(1);
    env = r.env; env.scheduler = 'pf'; if isfield(env, 'calib_sched'), env.scheduler = env.calib_sched; end; b0 = env.burn_in; n_eval = size(M.cell_tp{1}, 2);
    tpA2C = mean(M.cell_tp{8}, 1, 'omitnan');
    lc = r.learning_curves;
    fprintf(fid, '\n### SANITY %s\n', tag);
    kk = min(25, size(lc, 1));
    fprintf(fid, 'LC|%s|first25=%.4f|last25=%.4f\n', tag, mean(mean(lc(1:kk, :))), mean(mean(lc(end-kk+1:end, :))));
    offs = env.actions;
    tpR = zeros(1, n_eval); tpC = zeros(numel(offs), n_eval); blC = zeros(numel(offs), n_eval);
    for j = 1:n_eval
        rng(9000 + j);
        [Strue, ~, meta] = generateChannel_v9(200, env);
        obsS = cqiFeedback_v9(Strue, env, meta.delays); meta.trace_id = j; rng(50000 + j); U = rand(size(Strue));
        rng(79000 + 100*j);
        tp = evalPolicy_v9('rand', [], Strue, obsS, env, meta, U);
        tpR(j) = sum(mean(tp(b0+1:end, :), 1));
        for c = 1:numel(offs)
            envC = env; envC.fixed_offset = offs(c);
            rng(79500 + 100*j + c);
            [tp, bl] = evalPolicy_v9('fixed', [], Strue, obsS, envC, meta, U);
            tpC(c, j) = sum(mean(tp(b0+1:end, :), 1));
            blB = bl(b0+1:end, :); ok = ~isnan(blB); blC(c, j) = mean(blB(ok));
        end
    end
    fprintf(fid, 'RAND|%s|rand_tp=%.4f|a2c_tp=%.4f|a2c_vs_rand_pct=%.2f|wilcoxon=%.3g\n', ...
        tag, mean(tpR), mean(tpA2C), 100*(mean(tpA2C) - mean(tpR))/mean(tpR), signrank(tpA2C, tpR));
    for c = 1:numel(offs)
        fprintf(fid, 'CONST|%s|offset=%+d|tp=%.4f|bler1=%.4f\n', tag, offs(c), mean(tpC(c, :)), mean(blC(c, :)));
    end
end
