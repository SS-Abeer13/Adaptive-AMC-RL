function v = metricMean_v8(X, k, detK)
% metricMean_v8  Mean of a per-(seed x trace) metric matrix, ignoring rows
% that were never filled.
%
% AUDIT FIX (2026-09-29): runComparison_v8 evaluates deterministic schemes
% (k <= detK) only once (row 1) but the metric matrices were pre-allocated
% with zeros for all n_seeds rows. Averaging with nanmean(X(:)) therefore
% mixed (n_seeds-1) rows of zeros into every non-RL scheme, dividing their
% BLER / edge Tp / Jain / burst / calm figures by ~n_seeds (2x with 2 seeds).
% This helper uses row 1 for deterministic schemes and all rows for the RL
% scheme, so it also gives correct numbers for legacy .mat files.
    if nargin < 3 || isempty(detK), detK = 7; end
    if k <= detK
        X = X(1, :);
    end
    v = mean(X(:), 'omitnan');
end
