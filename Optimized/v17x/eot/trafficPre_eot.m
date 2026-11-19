function [Q, H, miss] = trafficPre_eot(Q, t, env, H)
% trafficPre_eot  Start of TTI t: expire packets past deadline and admit arrivals.
% Bit-identical to trafficPre_v17 under env.eot_mode = 'asrun'.
    N = numel(Q.has); miss = false(1, N);
    if ~Q.on, return; end
    Dv = userDeadline_v17(env, N);
    countTo = Inf;
    if isfield(Q, 'countTo'), countTo = Q.countTo; end
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
            if Q.arr(i) > Q.countFrom && Q.dl(i) <= countTo
                Q.resU(i) = Q.resU(i) + 1;
            end
        end
        if ~Q.has(i) && mod(t - 1 - Q.ph(i), env.pkt_period) == 0
            Q.has(i) = true;
            Q.rem(i) = env.pkt_bits;
            if isfield(Q, 'tx_rem'), Q.tx_rem(i) = env.pkt_bits; end
            Q.arr(i) = t; Q.dl(i) = t + Dv(i) - 1;

            % EOT arrival counting
            if isfield(Q, 'eot_track') && Q.arr(i) > Q.countFrom
                Q.eot_track.n_arrivals_all = Q.eot_track.n_arrivals_all + 1;
                if Q.dl(i) <= Q.eot_track.T_end
                    Q.eot_track.n_arrivals_resolved = Q.eot_track.n_arrivals_resolved + 1;
                end
            end
        end
    end
end
