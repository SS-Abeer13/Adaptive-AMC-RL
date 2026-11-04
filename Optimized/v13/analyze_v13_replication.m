function analyze_v13_replication(matFile, tag, fid, si)
% analyze_v13_replication  Pre-registered decision rules of PLAN_v13.md section S1.5.
%   matFile : results_v13_<tag>.mat ; fid : open summary file (1 = console) ; si : scheduler index (default 1)
% Writes REPLCMP| lines (one per comparator), REPLSEED| (seed consistency) and one REPL| verdict line.
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
    aK = find(strcmp(names, 'Deep A2C v13 (ensemble)'), 1);
    if isempty(aK), aK = find(strcmp(names, 'Deep A2C v13'), 1); end
    if isempty(aK), error('analyze_v13_replication: scheme "Deep A2C v13 (ensemble)" not found'); end
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
        error('analyze_v13_replication: comparator names changed; expected %s and %s', strjoin(famA, ','), strjoin(famB, ','));
    end
    claimA = all(pass(kA)); claimB = all(pass(kB)); win = all(pass(cmpK));
    % seed consistency: per-seed A2C mean vs the strongest calibrated rule (family B)
    [~, ib] = max(arrayfun(@(k) mean(per(k)), kB)); kbest = kB(ib);
    aInd = find(strcmp(names, 'Deep A2C v13'), 1);
    if isempty(aInd), aInd = aK; end
    seedM = mean(M.primary{aInd}, 2, 'omitnan')';
    nAbove = sum(seedM > mean(per(kbest)));
    fprintf(fid, 'REPLSEED|%s|%s|a2c_seed_means=%s|best_rule=%s(%.4f)|seeds_above=%d/%d\n', ...
        tag, sched, mat2str(round(seedM, 4)), names{kbest}, mean(per(kbest)), nAbove, numel(seedM));
    fprintf(fid, 'REPL|%s|%s|n_traces=%d|a2c=%.4f|claimA_olla_family=%d|claimB_calibrated_rules=%d|win_all=%d\n', ...
        tag, sched, n, mean(a), claimA, claimB, win);
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
