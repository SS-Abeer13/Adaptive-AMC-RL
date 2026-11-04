function D = userDeadline_v15(env, N)
% userDeadline_v15  Per-user latency budget (1 x N); a scalar pkt_deadline applies to all.
    d = env.pkt_deadline(:).';
    D = d(min(1:N, numel(d)));
    if numel(d) > 1 && numel(d) < N, D = d(mod((1:N) - 1, numel(d)) + 1); end
end
