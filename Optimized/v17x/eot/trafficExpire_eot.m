function [Q, H, miss] = trafficExpire_eot(Q, t, env, H)
% trafficExpire_eot  Expire packets past deadline during drain/end-of-trace.
% Expiry only, no new arrivals admitted.
    N = numel(Q.has); miss = false(1, N);
    if ~Q.on, return; end
    countTo = Inf;
    if isfield(Q, 'countTo'), countTo = Q.countTo; end
    for i = 1:N
        if Q.has(i) && t > Q.dl(i)
            miss(i) = true; Q.has(i) = false;

            % In resolved mode, track what asrun would have done
            if isfield(Q, 'eot_track') && Q.arr(i) > Q.countFrom
                would_late_ack = false;
                if isfield(H, 'proc_busy')
                    for p = 1:H.nproc
                        if H.proc_busy(i, p) && H.proc_ready_t(i, p) > 0 && ~H.proc_isRetx(i, p)
                            if H.proc_ok(i, p) && H.proc_bits(i, p) >= Q.rem(i) && H.proc_ready_t(i, p) > Q.dl(i) + 1
                                would_late_ack = true;
                            end
                        end
                    end
                end
                if would_late_ack
                    Q.eot_track.n_late_ack_asrun = Q.eot_track.n_late_ack_asrun + 1;
                else
                    Q.eot_track.n_censored_asrun = Q.eot_track.n_censored_asrun + 1;
                end
            end

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
    end
end
