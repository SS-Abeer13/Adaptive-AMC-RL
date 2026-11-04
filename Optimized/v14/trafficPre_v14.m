function [Q, H, miss] = trafficPre_v14(Q, t, env, H)
% trafficPre_v14  Start of TTI t: expire packets past their deadline (the
% pending HARQ process is flushed) and admit new arrivals.
    N = numel(Q.has); miss = false(1, N);
    if ~Q.on, return; end
    Dv = userDeadline_v14(env, N);
    for i = 1:N
        if Q.has(i) && t > Q.dl(i)
            miss(i) = true; Q.has(i) = false;
            H.pend(i) = false; H.nret(i) = 0;
            if Q.arr(i) > Q.countFrom, Q.resU(i) = Q.resU(i) + 1; end
        end
        if ~Q.has(i) && mod(t - 1 - Q.ph(i), env.pkt_period) == 0
            Q.has(i) = true; Q.rem(i) = env.pkt_bits;
            Q.arr(i) = t; Q.dl(i) = t + Dv(i) - 1;   % v14e: per-user budget
        end
    end
end
