function [Q, H, miss] = trafficExpire_eot(Q, t, env, H)
% trafficExpire_eot  Expire packets past deadline during drain/end-of-trace.
% Expiry only, no new arrivals admitted.
% (Note: Resolved-pass exposure heuristic marked unused per S_EOT_PF_prereg.md Section 2)
    N = numel(Q.has); miss = false(1, N);
    if ~Q.on, return; end
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
    end
end
