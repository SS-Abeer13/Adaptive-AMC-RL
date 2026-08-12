function [tp, off, H, bler1, nackEv] = txStep_v7(sent, Strue_row, rb, off, H, env)
% txStep_v7  One TTI of transmission physics: HARQ, Bernoulli delivery, OLLA update.
    N = numel(sent);
    tp = zeros(1, N); bler1 = nan(1, N); nackEv = false(1, N);
    du = env.olla_step_down * env.olla_target/(1 - env.olla_target);
    dd = env.olla_step_down;

    for i = 1:N
        if rb(i) <= 0, continue; end

        if env.harq_on && H.pend(i)
            % Retransmission (chase combining), no OLLA update
            effS = Strue_row(i) + env.harq_comb_dB * H.nret(i);
            bl   = estimateBLER_v7(effS, H.mcs(i));
            if rand > bl
                tp(i) = H.tbs(i) * 1e-3;
                H.pend(i) = false; H.nret(i) = 0;
            else
                H.nret(i) = H.nret(i) + 1;
                if H.nret(i) > env.harq_max_retx
                    H.pend(i) = false; H.nret(i) = 0;
                end
            end
        else
            % New transmission at the chosen CQI
            mcs = sent(i) - 1;
            bl  = estimateBLER_v7(Strue_row(i), mcs);
            bler1(i) = bl;
            TBS = tbsFromMCSandRB(mcs, rb(i));
            ack = rand > bl;
            if ack
                tp(i) = TBS * 1e-3;
                off(i) = off(i) + du;
            else
                nackEv(i) = true;
                off(i) = off(i) - dd;
                if env.harq_on
                    H.pend(i) = true; H.nret(i) = 1;
                    H.tbs(i) = TBS;  H.mcs(i) = mcs;
                end
            end
        end
    end
end
