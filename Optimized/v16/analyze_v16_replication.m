function analyze_v16_replication(matFile, tag, fid, si, schemeName)
% analyze_v16_replication  Pre-registered decision rules of PLAN_v16.md.
%   matFile    : results_v16_<tag>.mat ; fid : open summary file (1 = console) ; si : scheduler index (default 1)
%   schemeName : primary scheme to test (default: 'Deep A2C v16' or 'Deep A2C v13')
% Writes REPLCMP| lines (one per comparator), REPLSEED| (seed consistency) and
% REPL| lines for all three aggregators: per-seed (primary), ensemble and best-on-val (secondary).
% Each REPL line carries scheme=<name>.
%   Claim A  (OLLA family)          : A2C beats OLLA, OLLA (tuned target), Multi-OLLA
%   Claim B  (calibrated rules)     : A2C beats Fixed, FixedPU (Oracle), Context table
%   WIN      (criterion)            : A2C beats every non-RL comparator
% "beats" = Holm-adjusted two-sided Wilcoxon signed-rank p < 0.05 AND 90% CI lower bound of the
% mean paired difference > 0. Holm is applied over ALL non-RL comparators (same family as WIN).
    if nargin < 3 || isempty(fid), fid = 1; end
    if nargin < 4 || isempty(si), si = 1; end

    L = load(matFile, 'results'); r = L.results; M = r.metrics(si);
    names = r.schemes; K = numel(names);
    sched = 'pf'; if isfield(r, 'eval_schedulers'), sched = r.eval_schedulers{si}; end

    % Detect whether file uses v16 or v13 naming
    if any(strcmp(names, 'Deep A2C v16'))
        prefix = 'Deep A2C v16';
    else
        prefix = 'Deep A2C v13';
    end

    if nargin < 5 || isempty(schemeName)
        schemeName = prefix;
    end

    aK = find(strcmp(names, schemeName), 1);
    if isempty(aK)
        error('analyze_v16_replication: scheme "%s" not found in %s', schemeName, matFile);
    end

    isRL = contains(names, 'Deep ');
    cmpK = find(~isRL);
    per = @(k) mean(M.primary{k}, 1, 'omitnan');           % per-trace value (mean over seeds)
    a = per(aK); n = numel(a);
    famA = {'OLLA', 'OLLA (tuned target)', 'Multi-OLLA'};
    famB = {'Fixed', 'FixedPU (Oracle)', 'Context table'};

    pr = nan(1, K); pct = nan(1, K); lo = nan(1, K); hi = nan(1, K);
    for k = cmpK
        b = per(k); d = a - b; md = mean(d); se = std(d) / sqrt(n); bm = mean(b);
        ci = md + [-1 1] * tinv(0.95, n - 1) * se;
        pct(k) = 100 * md / bm; lo(k) = 100 * ci(1) / bm; hi(k) = 100 * ci(2) / bm;
        pr(k) = signrank(a, b);
    end
    ph = nan(1, K); ph(cmpK) = holm_local(pr(cmpK));
    pass = false(1, K); pass(cmpK) = ph(cmpK) < 0.05 & lo(cmpK) > 0;

    for k = cmpK
        fprintf(fid, 'REPLCMP|%s|%s|A2C vs %s|pct=%+.2f|ci90pct=[%.2f %.2f]|p=%.3g|holm=%.3g|beats=%d\n', ...
            tag, sched, names{k}, pct(k), lo(k), hi(k), pr(k), ph(k), pass(k));
    end

    inFam = @(fam) cmpK(ismember(names(cmpK), fam));
    kA = inFam(famA); kB = inFam(famB);
    if numel(kA) ~= numel(famA) || numel(kB) ~= numel(famB)
        error('analyze_v16_replication: comparator names changed; expected %s and %s', strjoin(famA, ','), strjoin(famB, ','));
    end

    % seed consistency: per-seed A2C mean vs the strongest calibrated rule (family B)
    [~, ib] = max(arrayfun(@(k) mean(per(k)), kB)); kbest = kB(ib);
    seedM = mean(M.primary{aK}, 2, 'omitnan')';
    nAbove = sum(seedM > mean(per(kbest)));
    fprintf(fid, 'REPLSEED|%s|%s|a2c_seed_means=%s|best_rule=%s(%.4f)|seeds_above=%d/%d\n', ...
        tag, sched, mat2str(round(seedM, 4)), names{kbest}, mean(per(kbest)), nAbove, numel(seedM));

    % Write REPL lines for all three aggregators -- but only for the primary
    % A2C-resid scheme itself (prefix), which is the only scheme with
    % "(ensemble)"/"(best-on-val)" variants. BUG FIX (README_v16.md B2 row
    % 5 / S3.3): this used to hardcode {prefix, prefix+"(ensemble)",
    % prefix+"(best-on-val)"} regardless of the schemeName argument, so a
    % call for e.g. "Deep PPO v16" or "Deep A2C v16 (offset)" silently
    % re-reported the primary A2C scheme's three REPL lines instead of its
    % own -- exactly the per-scheme REPL requirement B2 asked for, broken
    % for every scheme except the primary one.
    if strcmp(schemeName, prefix)
        aggregators = {prefix, sprintf('%s (ensemble)', prefix), sprintf('%s (best-on-val)', prefix)};
    else
        aggregators = {schemeName};
    end
    for ag = 1:numel(aggregators)
        aggName = aggregators{ag};
        aggIdx = find(strcmp(names, aggName), 1);
        if isempty(aggIdx), continue; end

        a_agg = per(aggIdx);
        pr_agg = nan(1, K); lo_agg = nan(1, K);
        for k = cmpK
            b = per(k); d = a_agg - b; md = mean(d); se = std(d) / sqrt(n); bm = mean(b);
            ci = md + [-1 1] * tinv(0.95, n - 1) * se;
            lo_agg(k) = 100 * ci(1) / bm;
            pr_agg(k) = signrank(a_agg, b);
        end
        ph_agg = nan(1, K); ph_agg(cmpK) = holm_local(pr_agg(cmpK));
        pass_agg = false(1, K); pass_agg(cmpK) = ph_agg(cmpK) < 0.05 & lo_agg(cmpK) > 0;

        claimA_agg = all(pass_agg(kA));
        claimB_agg = all(pass_agg(kB));
        win_agg = all(pass_agg(cmpK));

        fprintf(fid, 'REPL|%s|%s|scheme=%s|n_traces=%d|a2c=%.4f|claimA_olla_family=%d|claimB_calibrated_rules=%d|win_all=%d\n', ...
            tag, sched, aggName, n, mean(a_agg), claimA_agg, claimB_agg, win_agg);
    end
end

function adj = holm_local(p)
% Holm step-down adjustment (NaN-safe).
    adj = nan(size(p)); ok = find(~isnan(p)); m = numel(ok);
    [ps, o] = sort(p(ok)); run = 0;
    for i = 1:m
        run = max(run, min(1, (m - i + 1) * ps(i)));
        adj(ok(o(i))) = run;
    end
end
