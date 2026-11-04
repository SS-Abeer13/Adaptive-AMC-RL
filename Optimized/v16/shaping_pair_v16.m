function stats = shaping_pair_v16(fileShaped, fileUnshaped, fid, varargin)
% shaping_pair_v16  Paired shaping test of PLAN_v16.md (B2.2 and C4).
%   fileShaped   : results file with ontime_shaped (e.g. Y0_base)
%   fileUnshaped : results file with unshaped ontime (e.g. Y0_noshape)
%   fid          : open summary file handle (default 1 = console)
%
% Computes the per-trace difference (shaped - unshaped) for the primary scheme
% on identical traces and seeds, and tests significance with Wilcoxon signed-rank.

    if nargin < 3 || isempty(fid), fid = 1; end

    Ls = load(fileShaped, 'results'); rs = Ls.results;
    Lu = load(fileUnshaped, 'results'); ru = Lu.results;

    % Verify identical trace and crn seed bases
    if isfield(rs.env, 'trace_seed_base') && isfield(ru.env, 'trace_seed_base')
        if rs.env.trace_seed_base ~= ru.env.trace_seed_base
            error('shaping_pair_v16:mismatch', 'trace_seed_base mismatch (%d vs %d)', ...
                rs.env.trace_seed_base, ru.env.trace_seed_base);
        end
    end
    if isfield(rs.env, 'crn_seed_base') && isfield(ru.env, 'crn_seed_base')
        if rs.env.crn_seed_base ~= ru.env.crn_seed_base
            error('shaping_pair_v16:mismatch', 'crn_seed_base mismatch (%d vs %d)', ...
                rs.env.crn_seed_base, ru.env.crn_seed_base);
        end
    end

    % Primary scheme: Deep A2C v16 (or v13 fallback)
    names = rs.schemes;
    primaryName = 'Deep A2C v16';
    if ~any(strcmp(names, primaryName))
        primaryName = 'Deep A2C v13';
    end

    ks = find(strcmp(rs.schemes, primaryName), 1);
    ku = find(strcmp(ru.schemes, primaryName), 1);
    if isempty(ks) || isempty(ku)
        error('shaping_pair_v16:missing_scheme', 'Primary scheme "%s" not found in both files', primaryName);
    end

    Ms = rs.metrics(1);
    Mu = ru.metrics(1);

    % Per-trace values of the primary scheme (mean over seeds)
    a_shaped = mean(Ms.primary{ks}, 1, 'omitnan');
    a_unshaped = mean(Mu.primary{ku}, 1, 'omitnan');

    n = numel(a_shaped);
    d = a_shaped - a_unshaped;
    md = mean(d);
    se = std(d) / sqrt(n);
    ci90 = md + [-1 1] * tinv(0.95, n - 1) * se;

    base_val = mean(a_unshaped);
    pct = 100 * md / base_val;
    ci90pct = 100 * ci90 / base_val;
    p_wilc = signrank(a_shaped, a_unshaped);

    % Pre-registered decision rule (PLAN_v16.md C4):
    % - "shaping helps" if CI lower bound > 0 and Wilcoxon p < 0.05
    % - "shaping hurts" if CI upper bound < 0
    % - "no evidence" if CI contains 0
    if ci90(1) > 0 && p_wilc < 0.05
        verdict = 'shaping helps';
    elseif ci90(2) < 0 && p_wilc < 0.05
        verdict = 'shaping hurts';
    else
        verdict = 'no evidence';
    end

    % Per-seed paired difference (same training seed s vs s)
    n_seeds = size(Ms.primary{ks}, 1);
    seed_s_shaped = mean(Ms.primary{ks}, 2, 'omitnan')';
    seed_s_unshaped = mean(Mu.primary{ku}, 2, 'omitnan')';
    d_seed = seed_s_shaped - seed_s_unshaped;
    n_above = sum(d_seed > 0);

    fprintf(fid, 'SHAPE|diff=%+.4f|pct=%+.2f|ci90pct=[%.2f %.2f]|p=%.4g|verdict=%s|seed_diffs=%s|seeds_above=%d/%d\n', ...
        md, pct, ci90pct(1), ci90pct(2), p_wilc, verdict, mat2str(round(d_seed, 4)), n_above, n_seeds);

    stats.diff = md;
    stats.pct = pct;
    stats.ci90 = ci90;
    stats.ci90pct = ci90pct;
    stats.p = p_wilc;
    stats.verdict = verdict;
    stats.seed_diffs = d_seed;
    stats.seeds_above = n_above;
    stats.n_seeds = n_seeds;
end
