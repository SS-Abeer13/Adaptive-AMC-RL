function fill_actions_sweep_v9(matFile, tag, fid, n_tr_act, targets)
% fill_actions_sweep_v9  (a) A2C action distribution vs FixedPU per-class
% targets on held-out traces; (b) OLLA target-BLER sweep on the same
% held-out traces as the campaign, compared with the trained A2C.
    L = load(matFile, 'results'); r = L.results; M = r.metrics(1);
    env = r.env; env.scheduler = 'pf'; if isfield(env, 'calib_sched'), env.scheduler = env.calib_sched; end
    A = env.actions; nA = numel(A);
    A2Cs = r.policies.A2C; nS = numel(A2Cs);
    n_eval = size(M.cell_tp{1}, 2);
    T = 200; if isfield(env, 'simTime_eval'), T = env.simTime_eval; end
    b0 = env.burn_in;
    tpA2C = mean(M.cell_tp{8}, 1, 'omitnan');

    % ---- (a) action distribution ----
    cntA = zeros(1, nA); cntF = zeros(1, nA);
    agreeExact = 0; agreeNear = 0; nDec = 0; modalShare = [];
    for j = 1:n_tr_act
        rng(9000 + j);
        [Strue, ~, meta] = generateChannel_v9(T, env);
        obsS = cqiFeedback_v9(Strue, env, meta.delays); meta.trace_id = j; rng(50000 + j); U = rand(size(Strue));
        fIdx = zeros(1, env.N);
        for i = 1:env.N
            [dc, vc] = userClass_v9(meta.delays(i), mean(meta.speeds(:, i)));
            [~, fIdx(i)] = min(abs(A - env.fixed_class_tab(dc, vc)));
        end
        for s = 1:nS
            rng(77000 + 100*j + 80 + s);
            [~, ~, ~, act] = evalPolicy_v9('a2c_v9', A2Cs{s}, Strue, obsS, env, meta, U);
            act = act(b0+1:end, :);
            for i = 1:env.N
                ai = act(:, i);
                cntA = cntA + histcounts(ai, 0.5:1:nA+0.5);
                cntF(fIdx(i)) = cntF(fIdx(i)) + numel(ai);
                agreeExact = agreeExact + sum(ai == fIdx(i));
                agreeNear  = agreeNear  + sum(abs(ai - fIdx(i)) <= 1);
                nDec = nDec + numel(ai);
                modalShare(end+1) = max(histcounts(ai, 0.5:1:nA+0.5)) / numel(ai); %#ok<AGROW>
            end
        end
    end
    pA = 100*cntA/sum(cntA); pF = 100*cntF/sum(cntF);
    fprintf(fid, '\n### ACTIONS %s (traces=%d, seeds=%d)\n', tag, n_tr_act, nS);
    fprintf(fid, 'ACT|%s|actions=%s\n', tag, mat2str(A));
    fprintf(fid, 'ACT|%s|a2c_pct=%s\n', tag, mat2str(round(pA, 2)));
    fprintf(fid, 'ACT|%s|fixedpu_pct=%s\n', tag, mat2str(round(pF, 2)));
    fprintf(fid, 'ACT|%s|agree_exact_pct=%.2f|agree_within1_pct=%.2f|mean_user_modal_share_pct=%.2f|a2c_mean_offset=%.3f|fixedpu_mean_offset=%.3f\n', ...
        tag, 100*agreeExact/nDec, 100*agreeNear/nDec, 100*mean(modalShare), sum(pA.*A)/100, sum(pF.*A)/100);

    % ---- (b) OLLA target sweep ----
    if isempty(targets), return; end
    fprintf(fid, '\n### SWEEP %s (traces=%d)\n', tag, n_eval);
    best = -inf; bestTp = []; bestLbl = '';
    for P = targets
        for pt = {'olla', 'warm_olla'}
            envT = env; envT.olla_target = P;
            tpv = zeros(1, n_eval); blv = zeros(1, n_eval);
            for j = 1:n_eval
                rng(9000 + j);
                [Strue, ~, meta] = generateChannel_v9(T, env);
                obsS = cqiFeedback_v9(Strue, env, meta.delays); meta.trace_id = j; rng(50000 + j); U = rand(size(Strue));
                rng(78000 + 100*j + round(100*P));
                [tp, bl] = evalPolicy_v9(pt{1}, [], Strue, obsS, envT, meta, U);
                tpB = tp(b0+1:end, :); blB = bl(b0+1:end, :);
                tpv(j) = sum(mean(tpB, 1));
                ok = ~isnan(blB); blv(j) = mean(blB(ok));
            end
            pw = signrank(tpA2C, tpv);
            fprintf(fid, 'SWEEP|%s|%s|target=%.2f|tp=%.4f|bler1=%.4f|a2c_vs_pct=%.2f|wilcoxon=%.3g\n', ...
                tag, pt{1}, P, mean(tpv), mean(blv), 100*(mean(tpA2C) - mean(tpv))/mean(tpv), pw);
            if mean(tpv) > best, best = mean(tpv); bestTp = tpv; bestLbl = sprintf('%s@%.2f', pt{1}, P); end
        end
    end
    d = tpA2C - bestTp; md = mean(d); se = std(d)/sqrt(n_eval); base = mean(bestTp); m2 = 0.02*base;
    p2 = max(1 - tcdf((md + m2)/se, n_eval-1), 1 - tcdf((m2 - md)/se, n_eval-1));
    fprintf(fid, 'SWEEPBEST|%s|best=%s|tp=%.4f|a2c_tp=%.4f|pct=%.2f|wilcoxon=%.3g|tost2pct=%.3g\n', ...
        tag, bestLbl, base, mean(tpA2C), 100*md/base, signrank(tpA2C, bestTp), p2);
end
