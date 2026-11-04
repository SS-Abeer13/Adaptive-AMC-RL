function [Q, H, miss] = trafficPre_v15(Q, t, env, H)
% trafficPre_v15  Start of TTI t: expire packets past their deadline (flushing
% all HARQ processes for that user, including in-flight blocks) and admit new arrivals.
    N = numel(Q.has); miss = false(1, N);
    if ~Q.on, return; end
    Dv = userDeadline_v15(env, N);
    for i = 1:N
        if Q.has(i) && t > Q.dl(i)
            miss(i) = true; Q.has(i) = false;
            H.pend(i) = false; H.nret(i) = 0;
            if isfield(H, 'proc_busy')
                H.proc_busy(i, :)    = false;
                H.proc_isRetx(i, :)  = false;
                H.proc_bits(i, :)    = 0;
                H.proc_ready_t(i, :) = 0;
            end
            if Q.arr(i) > Q.countFrom, Q.resU(i) = Q.resU(i) + 1; end
        end
        if ~Q.has(i) && mod(t - 1 - Q.ph(i), env.pkt_period) == 0
            Q.has(i) = true;
            Q.rem(i) = env.pkt_bits;
            if isfield(Q, 'tx_rem'), Q.tx_rem(i) = env.pkt_bits; end
            Q.arr(i) = t; Q.dl(i) = t + Dv(i) - 1;
        end
    end
end
