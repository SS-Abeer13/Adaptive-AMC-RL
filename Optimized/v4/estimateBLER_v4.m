function BLER = estimateBLER_v4(sinr_dB, mcs)
% estimateBLER_v4  Per-MCS sigmoid BLER model, calibrated to the 10% design point.
%
%   BLER = 1 / (1 + exp(k_m * (sinr - c_m)))
%
% where c_m = th_m - ln(9)/k_m so that BLER(th_m) = 0.1 exactly: th_m are the
% CQI switching thresholds, i.e. a link operating *at* its threshold sits at
% the LTE/NR outer-loop design target of 10% BLER (TS 36.213), not at 50% as
% in the previous model (steepness was hard-coded to 0.2, overriding the
% per-MCS table and producing ~+/-20 dB transition widths).
%
% Per-MCS steepness k_m (1.2 .. 2.7 /dB) gives waterfall widths of ~2-4 dB,
% consistent with published AWGN link-level curves (e.g. Vienna LTE-A
% simulator). Replace mcs_params with measured curves for camera-ready.

    persistent th k c
    if isempty(th)
        mcs_params = [ ...
            -6.7, 1.2;   % MCS 0  (QPSK)
            -5.0, 1.3;   % MCS 1
            -3.2, 1.4;   % MCS 2
            -1.5, 1.5;   % MCS 3
             0.8, 1.6;   % MCS 4  (16-QAM)
             2.0, 1.8;   % MCS 5
             4.5, 1.9;   % MCS 6
             6.8, 2.0;   % MCS 7
             9.2, 2.1;   % MCS 8  (64-QAM)
            11.5, 2.2;   % MCS 9
            14.0, 2.3;   % MCS 10
            16.3, 2.4;   % MCS 11
            18.7, 2.5;   % MCS 12 (256-QAM)
            20.5, 2.6;   % MCS 13
            21.8, 2.7];  % MCS 14
        th = mcs_params(:, 1);
        k  = mcs_params(:, 2);
        c  = th - log(9) ./ k;   % BLER(th) = 0.1
    end

    m = max(0, min(14, round(mcs))) + 1;
    BLER = 1 ./ (1 + exp(k(m) .* (sinr_dB - c(m))));
    BLER = max(0, min(1, BLER));
end
