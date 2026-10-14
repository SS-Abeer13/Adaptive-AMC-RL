function fill_bc_diag_v8(o, n_seeds, bc_eps, ep_rl, n_eval, fid)
% fill_bc_diag_v8  Diagnostic: clone FixedPU (bc_eps episodes), then RL
% fine-tune (ep_rl episodes) from the same seed; compare clone, fine-tuned
% policy and FixedPU on the campaign's held-out traces (PF).
    env = defaultEnv_v8(23, o.N);
    fn = fieldnames(o);
    for f = 1:numel(fn)
        if isfield(env, fn{f}), env.(fn{f}) = o.(fn{f}); end
    end
    if isfield(o, 'sched_on_ref'), env.sched_on_ref = o.sched_on_ref; end
    env = calibrateFixedClass_v8(env, o.n_calib, o.simTime);
    env.scheduler = 'pf';
    T = o.simTime; b0 = env.burn_in;
    tpC = zeros(n_seeds, n_eval); tpF = zeros(n_seeds, n_eval); tpO = zeros(1, n_eval);
    blC = zeros(n_seeds, n_eval); blF = zeros(n_seeds, n_eval); blO = zeros(1, n_eval);
    entEndBC = zeros(1, n_seeds); entEndFT = zeros(1, n_seeds); entMin = zeros(1, n_seeds);
    nets = cell(2, n_seeds);
    for s = 1:n_seeds
        fprintf('  [BC diag] seed %d/%d %s\n', s, n_seeds, datestr(now, 'HH:MM:SS'));
        [nets{1, s}, ~, ~, e1] = DeepA2C_BC_v8(T, 0,     42 + 200 + s, env, bc_eps);
        [nets{2, s}, ~, ~, e2] = DeepA2C_BC_v8(T, ep_rl, 42 + 200 + s, env, bc_eps);
        entEndBC(s) = e1(end); entEndFT(s) = e2(end); entMin(s) = min(e2(bc_eps+1:end));
    end
    for j = 1:n_eval
        rng(9000 + j);
        [Strue, ~, meta] = generateChannel_v7(T, env);
        obsS = cqiFeedback_v8(Strue, env, meta.delays);
        rng(77000 + 100*j + 70 + 1);
        [tp, bl] = evalPolicy_v8('fixed_class', [], Strue, obsS, env, meta);
        [tpO(j), blO(j)] = summ(tp, bl, b0);
        for s = 1:n_seeds
            rng(77000 + 100*j + 80 + s);
            [tp, bl] = evalPolicy_v8('a2c_v8', nets{1, s}, Strue, obsS, env, meta);
            [tpC(s, j), blC(s, j)] = summ(tp, bl, b0);
            rng(77000 + 100*j + 80 + s);
            [tp, bl] = evalPolicy_v8('a2c_v8', nets{2, s}, Strue, obsS, env, meta);
            [tpF(s, j), blF(s, j)] = summ(tp, bl, b0);
        end
    end
    c = mean(tpC, 1); f = mean(tpF, 1);
    fprintf(fid, '\n### BCDIAG (seeds=%d, bc_eps=%d, rl_eps=%d, traces=%d)\n', n_seeds, bc_eps, ep_rl, n_eval);
    fprintf(fid, 'BC|class_tab=%s|fixed_offset=%d\n', mat2str(env.fixed_class_tab), env.fixed_offset);
    fprintf(fid, 'BC|clone_tp=%.4f|finetuned_tp=%.4f|fixedpu_tp=%.4f\n', mean(c), mean(f), mean(tpO));
    fprintf(fid, 'BC|clone_bler1=%.4f|finetuned_bler1=%.4f|fixedpu_bler1=%.4f\n', mean(blC(:)), mean(blF(:)), mean(blO));
    fprintf(fid, 'BC|finetune_minus_clone=%.4f|pct=%.2f|wilcoxon=%.3g\n', mean(f - c), 100*mean(f - c)/mean(c), signrank(f, c));
    fprintf(fid, 'BC|clone_vs_fixedpu_pct=%.2f|wilcoxon=%.3g\n', 100*(mean(c) - mean(tpO))/mean(tpO), signrank(c, tpO));
    fprintf(fid, 'BC|finetuned_vs_fixedpu_pct=%.2f|wilcoxon=%.3g\n', 100*(mean(f) - mean(tpO))/mean(tpO), signrank(f, tpO));
    fprintf(fid, 'BC|entropy_end_BC=%s|entropy_min_FT=%s|entropy_end_FT=%s|max=%.3f\n', ...
        mat2str(round(entEndBC, 3)), mat2str(round(entMin, 3)), mat2str(round(entEndFT, 3)), log(numel(env.actions)));
    fprintf(fid, 'BC|per_seed_ft_minus_clone_pct=%s\n', mat2str(round(100*(mean(tpF, 2) - mean(tpC, 2))' ./ mean(tpC, 2)', 2)));
end

function [tpv, blv] = summ(tp, bl, b0)
    tpB = tp(b0+1:end, :); blB = bl(b0+1:end, :);
    tpv = sum(mean(tpB, 1)); ok = ~isnan(blB); blv = mean(blB(ok));
end
