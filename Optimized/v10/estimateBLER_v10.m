function BLER = estimateBLER_v10(sinr_dB, mcs)
% estimateBLER_v10  Per-MCS 3GPP AWGN waterfall link abstraction.
% Mathematical model:
%   BLER(gamma, m) = 1 / (1 + exp(k_m * (gamma - c_m)))
% where:
%   gamma is effective SINR in dB (including Chase combining gain)
%   m in {0, ..., 14} is the 3GPP MCS index
%   k_m in [3.0, 5.8] is the sigmoidal waterfall transition steepness
%   c_m = th_m - log(9)/k_m anchors the threshold at exactly BLER = 0.10 (10%)
    persistent th k c
    if isempty(th)
        % [SINR_threshold_at_10%_BLER_dB, steepness_factor_k]
        mcs_params = [ ...
            -6.7, 3.0; ... % MCS 0 (QPSK, rate ~0.15)
            -5.0, 3.2; ... % MCS 1 (QPSK, rate ~0.23)
            -3.2, 3.4; ... % MCS 2 (QPSK, rate ~0.38)
            -1.5, 3.6; ... % MCS 3 (QPSK, rate ~0.60)
             0.8, 3.8; ... % MCS 4 (QPSK, rate ~0.88)
             2.0, 4.0; ... % MCS 5 (16QAM, rate ~1.18)
             4.5, 4.2; ... % MCS 6 (16QAM, rate ~1.48)
             6.8, 4.4; ... % MCS 7 (16QAM, rate ~1.91)
             9.2, 4.6; ... % MCS 8 (16QAM, rate ~2.41)
            11.5, 4.8; ... % MCS 9 (64QAM, rate ~2.73)
            14.0, 5.0; ... % MCS 10 (64QAM, rate ~3.32)
            16.3, 5.2; ... % MCS 11 (64QAM, rate ~3.90)
            18.7, 5.4; ... % MCS 12 (64QAM, rate ~4.52)
            20.5, 5.6; ... % MCS 13 (64QAM, rate ~5.12)
            21.8, 5.8];    % MCS 14 (64QAM, rate ~5.55)
        th = mcs_params(:, 1);
        k  = mcs_params(:, 2);
        c  = th - log(9) ./ k;
    end
    m = max(0, min(14, round(mcs))) + 1;
    BLER = 1 ./ (1 + exp(k(m) .* (sinr_dB - c(m))));
    BLER = max(0, min(1, BLER));
end
