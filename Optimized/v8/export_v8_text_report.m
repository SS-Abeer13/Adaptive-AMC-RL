% export_v8_text_report.m
% Re-export a text report from a saved results_v8_<tag>.mat.
%
% AUDIT FIXES (2026-09-29):
%   - results.metrics is a 1 x nSched struct array (PF, RR, ...); the old
%     script indexed it as a scalar (M.cell_tp{1}) and errored. Now loops over
%     every evaluated scheduler.
%   - Uses metricMean_v8 so the zero-padded rows in legacy .mat files are
%     excluded (the old tables under-reported non-RL schemes by ~n_seeds x).
%   - Adds Holm-Bonferroni adjusted p-values.
%   - Writes results_v8_<tag>_recomputed.txt instead of overwriting the
%     original results_v8_<tag>.txt produced by runComparison_v8.
if ~exist('tag', 'var') || isempty(tag), tag = 'headline'; end
here = fileparts(mfilename('fullpath'));
addpath(here);
outDir = fullfile(here, 'Dataset');
matPath = fullfile(outDir, sprintf('results_v8_%s.mat', tag));
txtPath = fullfile(outDir, sprintf('results_v8_%s_recomputed.txt', tag));

if ~exist(matPath, 'file')
    error('%s not found', matPath);
end

data = load(matPath);
res = data.results;
env = res.env;
schemes = res.schemes;
K = numel(schemes);
detK = K - 1;                       % all but the RL scheme are single-run
scheds = res.eval_schedulers;
eq_margin = 0.10;                   % Mbps (same as runComparison_v8)

fid = fopen(txtPath, 'w');
fprintf(fid, '========================================================================\n');
fprintf(fid, 'RL-AMC v8 EVALUATION REPORT [%s] (re-computed from .mat)\n', upper(tag));
fprintf(fid, 'N=%d | BW=20 MHz | RB=100 | NoiseFloor=%.1f dBm | Hetero=%.2f | Burst=+%g dB\n', ...
        env.N, env.noise_floor_dBm, env.hetero, env.burst_IM_dB);
fprintf(fid, 'HARQ=%d | StateTier=%s | Actions=%s | Zero-BC (bc_warm_eps=%d)\n', ...
        env.harq_on, env.state_tier, mat2str(env.actions), env.bc_warm_eps);
fprintf(fid, 'Seeds=%d | Traces=%d | Exported: %s\n', size(res.metrics(1).cell_tp{K}, 1), ...
        size(res.metrics(1).cell_tp{1}, 2), datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, '========================================================================\n\n');

for sc = 1:numel(res.metrics)
    M = res.metrics(sc);
    n_eval = size(M.cell_tp{1}, 2);
    fprintf(fid, '---- SCHEDULER: %s ----\n', upper(scheds{sc}));
    fprintf(fid, '  %-20s | %-16s | %-8s | %-8s | %-8s | %-12s\n', ...
            'Scheme', 'Cell Tp (Mbps)', 'BLER1', 'Edge Tp', 'Jain', 'Burst / Calm');
    fprintf(fid, '----------------------------------------------------------------------------------------\n');

    tp_all = cell(1, K);
    for k = 1:K
        if k <= detK, tp_k = M.cell_tp{k}(1, :); else, tp_k = mean(M.cell_tp{k}, 1); end
        tp_all{k} = tp_k;
        fprintf(fid, '  %-20s | %5.2f +/- %4.2f   | %5.3f  | %5.2f   | %5.3f  | %4.2f / %4.2f Mbps\n', ...
                schemes{k}, mean(tp_k), 1.96 * std(tp_k) / sqrt(n_eval), ...
                metricMean_v8(M.bler{k}, k, detK), metricMean_v8(M.edge_tp{k}, k, detK), ...
                metricMean_v8(M.jain{k}, k, detK), metricMean_v8(M.tp_burst{k}, k, detK), ...
                metricMean_v8(M.tp_calm{k}, k, detK));
    end
    fprintf(fid, '========================================================================================\n\n');

    fprintf(fid, 'STATISTICAL SIGNIFICANCE & TOST EQUIVALENCE TESTING (Deep A2C vs. Comparators):\n');
    tp_a2c = tp_all{K};
    p_raw = nan(1, detK);
    for k = 1:detK
        if exist('signrank', 'file') == 2, p_raw(k) = signrank(tp_a2c, tp_all{k}); end
    end
    p_holm = holmAdjust_v8(p_raw);
    for k = 1:detK
        delta = tp_a2c - tp_all{k};
        mean_diff = mean(delta);
        se_diff = std(delta) / sqrt(n_eval);
        p_equiv = max(1 - tcdf((mean_diff + eq_margin) / (se_diff + eps), n_eval - 1), ...
                      1 - tcdf((eq_margin - mean_diff) / (se_diff + eps), n_eval - 1));
        equiv_str = 'NON-EQUIVALENT';
        if p_equiv < 0.05, equiv_str = 'EQUIVALENT'; end
        fprintf(fid, '  vs. %-18s : Delta = %+5.2f Mbps (%+5.1f%%) | Wilcoxon p = %7.4g (Holm %7.4g) | TOST p = %7.4g [%s]\n', ...
                schemes{k}, mean_diff, 100 * mean_diff / max(mean(tp_all{k}), eps), ...
                p_raw(k), p_holm(k), p_equiv, equiv_str);
    end
    fprintf(fid, '\n');
end
fclose(fid);
fprintf('Text report generated: %s\n', txtPath);
