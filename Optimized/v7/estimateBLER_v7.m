function BLER = estimateBLER_v7(sinr_dB, mcs)
% estimateBLER_v7  Per-MCS BLER waterfall: BLER = 1/(1+exp(k_m*(sinr-c_m))).
    persistent th k c
    if isempty(th)
        mcs_params = [ ...
            -6.7, 3.0; -5.0, 3.2; -3.2, 3.4; -1.5, 3.6;  0.8, 3.8; ...
             2.0, 4.0;  4.5, 4.2;  6.8, 4.4;  9.2, 4.6; 11.5, 4.8; ...
            14.0, 5.0; 16.3, 5.2; 18.7, 5.4; 20.5, 5.6; 21.8, 5.8];
        th = mcs_params(:, 1); k = mcs_params(:, 2);
        c  = th - log(9) ./ k;
    end
    m = max(0, min(14, round(mcs))) + 1;
    BLER = 1 ./ (1 + exp(k(m) .* (sinr_dB - c(m))));
    BLER = max(0, min(1, BLER));
end
