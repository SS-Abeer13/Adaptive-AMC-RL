function [num, den, cellv] = userMetric_v12(env, tp, info, b0)
% userMetric_v12  Per-user numerator/denominator of the primary metric and
% the cell-level value. goodput: per-user mean Mbps after burn-in (cell =
% sum); ontime: packets delivered within deadline / packets resolved
% (cell = pooled ratio).
    N = size(tp, 2);
    if isfield(env, 'primary') && strcmpi(env.primary, 'ontime')
        num = info.okU; den = info.resU;
        cellv = sum(num) / max(sum(den), 1);
    else
        num = mean(tp(b0+1:end, :), 1); den = ones(1, N);
        cellv = sum(num);
    end
end
