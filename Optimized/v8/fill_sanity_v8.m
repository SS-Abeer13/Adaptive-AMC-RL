function fill_sanity_v8(ds, fid)
% fill_sanity_v8  Is the from-scratch A2C learning at all?
%  (1) learning-curve trend per point, (2) uniform-random action control,
%  (3) constant-offset landscape on the headline held-out traces.
    tags = {'fill_headline', 'fill_tierA', 'fill_tierO', 'fill_steady1000'};
    fprintf(fid, '\n### SANITY (%s)\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    for t = 1:numel(tags)
        f = fullfile(ds, ['results_v8_' tags{t} '.mat']);
        if ~exist(f, 'file'), continue; end
        L = load(f, 'results'); lc = L.results.learning_curves; ec = L.results.entropy_curves;
        k = min(25, floor(size(lc, 1)/4));
        fprintf(fid, 'LC|%s|first%d=%.4f|last%d=%.4f|first_ent=%.3f|last_ent=%.3f|per_seed_last=%s\n', tags{t}, k, ...
            mean(mean(lc(1:k, :))), k, mean(mean(lc(end-k+1:end, :))), mean(mean(ec(1:k, :))), ...
            mean(mean(ec(end-k+1:end, :))), mat2str(round(mean(lc(end-k+1:end, :), 1), 3)));
    end
    L = load(fullfile(ds, 'results_v8_fill_headline.mat'), 'results'); r = L.results; M = r.metrics(1);
    env = r.env; env.scheduler = 'pf'; b0 = env.burn_in; n_eval = size(M.cell_tp{1}, 2);
    tpA2C = mean(M.cell_tp{8}, 1, 'omitnan'); tpPU = M.cell_tp{7}(1, :);
    offs = env.actions;
    tpR = zeros(1, n_eval); tpC = zeros(numel(offs), n_eval); blC = zeros(numel(offs), n_eval);
    for j = 1:n_eval
        rng(9000 + j);
        [Strue, ~, meta] = generateChannel_v7(200, env);
        obsS = cqiFeedback_v8(Strue, env, meta.delays);
        rng(79000 + 100*j);
        tp = evalPolicy_v8('rand', [], Strue, obsS, env, meta);
        tpR(j) = sum(mean(tp(b0+1:end, :), 1));
        for c = 1:numel(offs)
            envC = env; envC.fixed_offset = offs(c);
            rng(79500 + 100*j + c);
            [tp, bl] = evalPolicy_v8('fixed', [], Strue, obsS, envC, meta);
            tpC(c, j) = sum(mean(tp(b0+1:end, :), 1));
            blB = bl(b0+1:end, :); ok = ~isnan(blB); blC(c, j) = mean(blB(ok));
        end
    end
    fprintf(fid, 'RAND|headline|rand_tp=%.4f|a2c_tp=%.4f|fixedpu_tp=%.4f|a2c_vs_rand_pct=%.2f|wilcoxon=%.3g\n', ...
        mean(tpR), mean(tpA2C), mean(tpPU), 100*(mean(tpA2C) - mean(tpR))/mean(tpR), signrank(tpA2C, tpR));
    for c = 1:numel(offs)
        fprintf(fid, 'CONST|headline|offset=%+d|tp=%.4f|bler1=%.4f\n', offs(c), mean(tpC(c, :)), mean(blC(c, :)));
    end
end
