function [tp, off, H, bler1, nackEv, dropEv] = txStep_v8(sent, Strue_row, rb, off, H, env)
% txStep_v8  v8 transmission physics: HARQ Chase combining, outer-loop tracking,
% and unconstrained retransmission accounting.
%
% Outputs:
%   tp     : Delivered throughput in Mbps per user (scaled from TBS)
%   off    : Updated OLLA offsets per user
%   H      : Updated HARQ state structure
%   bler1  : First-transmission BLER (NaN if not a first transmission)
%   nackEv : Logical array indicating NACK event at this TTI
%   dropEv : Logical array indicating dropped packet event (exceeded max retx)
    N = numel(sent);
    tp = zeros(1, N);
    bler1 = nan(1, N);
    nackEv = false(1, N);
    dropEv = false(1, N);

    du = env.olla_step_down * env.olla_target / (1 - env.olla_target);
    dd = env.olla_step_down;

    for i = 1:N
        if rb(i) <= 0, continue; end

        if env.harq_on && H.pend(i)
            % -------------------------------------------------------------
            % HARQ Retransmission with Chase Combining
            % -------------------------------------------------------------
            effS = Strue_row(i) + env.harq_comb_dB * H.nret(i);
            bl = estimateBLER_v8(effS, H.mcs(i));
            ack = (rand > bl);

            if ack
                tp(i) = H.tbs(i) * 1e-3;
                H.pend(i) = false;
                H.nret(i) = 0;
                % In v8, adaptive tracking registers retransmission recovery
                off(i) = off(i) + 0.5 * du;
            else
                nackEv(i) = true;
                H.nret(i) = H.nret(i) + 1;
                if H.nret(i) > env.harq_max_retx
                    % Dropped packet: buffer flushed
                    dropEv(i) = true;
                    H.pend(i) = false;
                    H.nret(i) = 0;
                    off(i) = off(i) - dd;
                else
                    off(i) = off(i) - 0.5 * dd;
                end
            end
        else
            % -------------------------------------------------------------
            % Initial Transmission (New Transport Block)
            % -------------------------------------------------------------
            mcs = max(0, min(14, sent(i) - 1));
            bl = estimateBLER_v8(Strue_row(i), mcs);
            bler1(i) = bl;
            TBS = tbsFromMCSandRB(mcs, rb(i));
            ack = (rand > bl);

            if ack
                tp(i) = TBS * 1e-3;
                off(i) = off(i) + du;
            else
                nackEv(i) = true;
                off(i) = off(i) - dd;
                if env.harq_on
                    H.pend(i) = true;
                    H.nret(i) = 1;
                    H.tbs(i)  = TBS;
                    H.mcs(i)  = mcs;
                else
                    dropEv(i) = true;
                end
            end
        end
        % Anti-windup bound on the OLLA offset (see defaultEnv_v8.olla_off_lim)
        if isfield(env, 'olla_off_lim') && ~isempty(env.olla_off_lim)
            off(i) = max(-env.olla_off_lim, min(env.olla_off_lim, off(i)));
        end
    end
end
