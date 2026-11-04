function p_adj = holmAdjust_v17(p)
% holmAdjust_v17  Holm-Bonferroni step-down adjusted p-values (NaN-safe).
    p_adj = nan(size(p));
    ok = find(~isnan(p));
    m = numel(ok);
    if m == 0, return; end
    [ps, ord] = sort(p(ok));
    adj = min(1, (m:-1:1) .* ps);
    adj = cummax(adj);
    p_adj(ok(ord)) = adj;
end
