function [sl, has, rf] = slackOf_v12(env, Q, t)
% slackOf_v12  Deadline slack in TTIs (Inf if no packet), packet flag,
% remaining-bits fraction.
    N = numel(Q.has);
    sl = inf(1, N); has = double(Q.has); rf = zeros(1, N);
    if ~Q.on, return; end
    sl(Q.has) = Q.dl(Q.has) - t + 1;          % TTIs left including this one
    rf(Q.has) = max(0, Q.rem(Q.has)) / env.pkt_bits;
end
