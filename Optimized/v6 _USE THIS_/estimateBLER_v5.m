function BLER = estimateBLER_v5(sinr_dB, mcs)
% estimateBLER_v5  Per-MCS sigmoid BLER, calibrated so BLER(threshold)=0.1
% (the LTE/NR outer-loop design point). Identical to optimized/v4.
%   BLER = 1/(1+exp(k_m*(sinr - c_m))),  c_m = th_m - ln(9)/k_m.

    persistent th k c
    if isempty(th)
        mcs_params = [ ...
            -6.7, 1.2; -5.0, 1.3; -3.2, 1.4; -1.5, 1.5;  0.8, 1.6; ...
             2.0, 1.8;  4.5, 1.9;  6.8, 2.0;  9.2, 2.1; 11.5, 2.2; ...
            14.0, 2.3; 16.3, 2.4; 18.7, 2.5; 20.5, 2.6; 21.8, 2.7];
        th = mcs_params(:, 1); k = mcs_params(:, 2);
        c  = th - log(9) ./ k;
    end
    m = max(0, min(14, round(mcs))) + 1;
    BLER = 1 ./ (1 + exp(k(m) .* (sinr_dB - c(m))));
    BLER = max(0, min(1, BLER));
end
