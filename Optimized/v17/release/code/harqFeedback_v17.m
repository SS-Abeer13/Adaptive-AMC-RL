function [H, Q, off, ackEv, nackEv, dropEv, tp_ack, fbList] = harqFeedback_v17(H, Q, off, env, t, du, dd)
% harqFeedback_v17  Stage A step 1: feedback arrival at TTI t (PLAN_v17 A2).
% For every process with ready_t == t:
%   ACK  : OLLA up-step; credit useful bits to packet (trafficPost); free process.
%   NACK : OLLA down-step. If nret + 1 > max_retx, drop block (drop update, return bits
%          to untransmitted, free process). Otherwise mark retx-ready with nret + 1.
    N = numel(off);
    ackEv  = false(1, N);
    nackEv = false(1, N);
    dropEv = false(1, N);
    tp_ack = zeros(1, N);
    fbList = struct('user', {}, 'dec_id', {}, 'is_ack', {}, 'bits', {}, 'completed', {}, 'nret', {});

    if ~isfield(H, 'proc_busy') || H.rtt <= 0
        return;
    end

    if isscalar(du), du = du * ones(1, N); end
    if isscalar(dd), dd = dd * ones(1, N); end

    for i = 1:N
        for p = 1:H.nproc
            if H.proc_busy(i, p) && H.proc_ready_t(i, p) == t && ~H.proc_isRetx(i, p)
                is_ack = H.proc_ok(i, p);
                if is_ack
                    ackEv(i) = true;
                    if H.proc_nret(i, p) > 0
                        off(i) = off(i) + 0.5 * du(i);
                    else
                        off(i) = off(i) + du(i);
                    end
                    
                    % Credit useful bits
                    tb_bits = H.proc_bits(i, p);
                    tp_mbps = tb_bits * 1e-3;
                    tp_ack(i) = tp_ack(i) + tp_mbps;
                    
                    ok_pkt = false;
                    if Q.on && Q.has(i)
                        Q.rem(i) = Q.rem(i) - tb_bits;
                        if Q.rem(i) <= 0
                            ok_pkt = true;
                            Q.has(i) = false;
                            if Q.arr(i) > Q.countFrom
                                Q.okU(i) = Q.okU(i) + 1;
                                Q.resU(i) = Q.resU(i) + 1;
                            end
                        end
                    end
                    
                    % Free process
                    H.proc_busy(i, p)    = false;
                    H.proc_isRetx(i, p)  = false;
                    H.proc_ready_t(i, p) = 0;
                    
                    idx = numel(fbList) + 1;
                    fbList(idx).user      = i;
                    fbList(idx).dec_id    = H.proc_dec_id(i, p);
                    fbList(idx).is_ack    = true;
                    fbList(idx).bits      = tb_bits;
                    fbList(idx).completed = ok_pkt;
                    fbList(idx).nret      = H.proc_nret(i, p);
                else
                    nackEv(i) = true;
                    next_nret = H.proc_nret(i, p) + 1;
                    if next_nret > env.harq_max_retx
                        dropEv(i) = true;
                        off(i)    = off(i) - dd(i);
                        if Q.on && Q.has(i) && isfield(Q, 'tx_rem')
                            Q.tx_rem(i) = Q.tx_rem(i) + H.proc_bits(i, p);
                        end
                        H.proc_busy(i, p)    = false;
                        H.proc_isRetx(i, p)  = false;
                        H.proc_ready_t(i, p) = 0;
                        
                        idx = numel(fbList) + 1;
                        fbList(idx).user      = i;
                        fbList(idx).dec_id    = H.proc_dec_id(i, p);
                        fbList(idx).is_ack    = false;
                        fbList(idx).bits      = 0;
                        fbList(idx).completed = false;
                        fbList(idx).nret      = next_nret;
                    else
                        if H.proc_nret(i, p) > 0
                            off(i) = off(i) - 0.5 * dd(i);
                        else
                            off(i) = off(i) - dd(i);
                        end
                        H.proc_isRetx(i, p) = true;
                        H.proc_nret(i, p)   = next_nret;
                        
                        idx = numel(fbList) + 1;
                        fbList(idx).user      = i;
                        fbList(idx).dec_id    = H.proc_dec_id(i, p);
                        fbList(idx).is_ack    = false;
                        fbList(idx).bits      = 0;
                        fbList(idx).completed = false;
                        fbList(idx).nret      = next_nret;
                    end
                end
            end
        end
    end

    % Anti-windup bound on OLLA offset
    if isfield(env, 'olla_off_lim') && ~isempty(env.olla_off_lim)
        off = max(-env.olla_off_lim, min(env.olla_off_lim, off));
    end

    % Synchronize H.pend and H.nret
    for i = 1:N
        retx_procs = find(H.proc_isRetx(i, :));
        H.pend(i) = ~isempty(retx_procs);
        if H.pend(i)
            p1 = retx_procs(1);
            H.nret(i) = H.proc_nret(i, p1);
            H.mcs(i)  = H.proc_mcs(i, p1);
            H.tbs(i)  = H.proc_tbs(i, p1);
        else
            H.nret(i) = 0;
        end
    end
end
