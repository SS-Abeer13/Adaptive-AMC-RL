function [H, Q, bler1, isRetxTx] = harqTransmit_v17(sent, Strue_row, rb, H, Q, env, t, u, dec_ids)
% harqTransmit_v17  Stage A step 4: Transmission physics under multi-process HARQ (PLAN_v17 A2).
% For scheduled users (rb > 0):
%   - Retransmission: uses stored MCS and Chase-combined SINR.
%   - New transmission: allocates a free process, computes BLER, useful bits, draws outcome,
%     and sets ready_t = t + max(harq_rtt, 1).
    N = numel(sent);
    bler1 = nan(1, N);
    isRetxTx = false(1, N);

    idx = find(rb > 0);
    if isempty(idx), return; end

    if nargin < 8 || isempty(u)
        ui = rand(1, numel(idx));
    else
        ui = u(idx);
    end

    if nargin < 9 || isempty(dec_ids)
        dec_ids = zeros(1, N);
    end

    for k = 1:numel(idx)
        i = idx(k);
        % Retransmission priority
        retx_procs = find(H.proc_isRetx(i, :));
        if ~isempty(retx_procs)
            p = retx_procs(1);
            isRetxTx(i) = true;
            mcs = H.proc_mcs(i, p);
            effS = Strue_row(i) + env.harq_comb_dB * H.proc_nret(i, p);
            bl = estimateBLER_v17(effS, mcs);
            ok = (ui(k) > bl);

            H.proc_isRetx(i, p)  = false;
            H.proc_ok(i, p)      = ok;
            H.proc_ready_t(i, p) = t + max(env.harq_rtt, 1);
            bler1(i) = NaN;
        else
            free_procs = find(~H.proc_busy(i, :));
            if ~isempty(free_procs)
                p = free_procs(1);
                mcs = max(0, min(14, sent(i) - 1));
                bl = estimateBLER_v17(Strue_row(i), mcs);
                bler1(i) = bl;
                tbs = tbsFromMCSandRB_v17(mcs, rb(i));
                if Q.on && isfield(Q, 'tx_rem')
                    useful_bits = min(tbs, max(0, Q.tx_rem(i)));
                    Q.tx_rem(i) = Q.tx_rem(i) - useful_bits;
                else
                    useful_bits = tbs;
                end
                ok = (ui(k) > bl);

                H.proc_busy(i, p)    = true;
                H.proc_ready_t(i, p) = t + max(env.harq_rtt, 1);
                H.proc_isRetx(i, p)  = false;
                H.proc_nret(i, p)    = 0;
                H.proc_mcs(i, p)     = mcs;
                H.proc_tbs(i, p)     = tbs;
                H.proc_bits(i, p)    = useful_bits;
                H.proc_ok(i, p)      = ok;
                H.proc_dec_id(i, p)  = dec_ids(i);
            end
        end
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
