% export_v8_text_report.m
addpath('Optimized/v8');
outDir = fullfile('Optimized', 'v8', 'Dataset');
matPath = fullfile(outDir, 'results_v8_headline.mat');
txtPath = fullfile(outDir, 'results_v8_headline.txt');

if ~exist(matPath, 'file')
    error('results_v8_headline.mat not found');
end

data = load(matPath);
res = data.results;
env = res.env;
M = res.metrics;
schemes = res.schemes;
K = numel(schemes);
n_eval = size(M.cell_tp{1}, 2);
n_seeds = size(M.cell_tp{K}, 1);

fid = fopen(txtPath, 'w');
fprintf(fid, '========================================================================\n');
fprintf(fid, 'RL-AMC v8 HEADLINE EVALUATION REPORT\n');
fprintf(fid, 'N=%d | BW=20 MHz | RB=100 | NoiseFloor=%.1f dBm | Hetero=%.2f | Burst=+%g dB\n', ...
        env.N, env.noise_floor_dBm, env.hetero, env.burst_IM_dB);
fprintf(fid, 'HARQ=%d | StateTier=%s | Actions=%s | Zero-BC (bc_warm_eps=%d)\n', ...
        env.harq_on, env.state_tier, mat2str(env.actions), env.bc_warm_eps);
fprintf(fid, 'Seeds=%d | Traces=%d | Saved: %s\n', ...
        n_seeds, n_eval, datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, '========================================================================\n\n');

fprintf(fid, '---- SCHEDULER: PF ----\n');
fprintf(fid, '  %-20s | %-16s | %-8s | %-8s | %-8s | %-12s\n', ...
        'Scheme', 'Cell Tp (Mbps)', 'BLER1', 'Edge Tp', 'Jain', 'Burst / Calm');
fprintf(fid, '----------------------------------------------------------------------------------------\n');

tp_all = cell(1, K);
for k = 1:K
    if k <= 7
        tp_k = M.cell_tp{k}(1, :);
    else
        tp_k = mean(M.cell_tp{k}, 1);
    end
    tp_all{k} = tp_k;

    mean_tp = mean(tp_k);
    ci_tp   = 1.96 * std(tp_k) / sqrt(n_eval);
    mean_bl = nanmean(M.bler{k}(:));
    mean_ed = nanmean(M.edge_tp{k}(:));
    mean_jn = nanmean(M.jain{k}(:));
    mean_bu = nanmean(M.tp_burst{k}(:));
    mean_ca = nanmean(M.tp_calm{k}(:));

    fprintf(fid, '  %-20s | %5.2f +/- %4.2f   | %5.3f  | %5.2f   | %5.3f  | %4.2f / %4.2f Mbps\n', ...
            schemes{k}, mean_tp, ci_tp, mean_bl, mean_ed, mean_jn, mean_bu, mean_ca);
end
fprintf(fid, '========================================================================================\n\n');

fprintf(fid, 'STATISTICAL SIGNIFICANCE & TOST EQUIVALENCE TESTING (Deep A2C vs. Comparators):\n');
tp_a2c = tp_all{8};
for k = 1:7
    tp_comp = tp_all{k};
    delta = tp_a2c - tp_comp;
    mean_diff = mean(delta);
    pct_gain  = 100 * mean_diff / max(mean(tp_comp), eps);

    if exist('signrank', 'file') == 2
        p_wilc = signrank(tp_a2c, tp_comp);
    else
        p_wilc = NaN;
    end

    eq_margin = 0.10;
    se_diff = std(delta) / sqrt(n_eval);
    t1 = (mean_diff - (-eq_margin)) / (se_diff + eps);
    t2 = (eq_margin - mean_diff) / (se_diff + eps);
    p_tost1 = 1 - tcdf(t1, n_eval - 1);
    p_tost2 = 1 - tcdf(t2, n_eval - 1);
    p_equiv = max(p_tost1, p_tost2);

    equiv_str = 'NON-EQUIVALENT';
    if p_equiv < 0.05, equiv_str = 'EQUIVALENT'; end

    fprintf(fid, '  vs. %-18s : Delta = %+5.2f Mbps (%+5.1f%%) | Wilcoxon p = %7.4g | TOST p = %7.4g [%s]\n', ...
            schemes{k}, mean_diff, pct_gain, p_wilc, p_equiv, equiv_str);
end
fclose(fid);
fprintf('Text report generated: %s\n', txtPath);
