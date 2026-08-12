function BLER = estimateBLER_Enhanced(sinr, mcs)
    % MCS-dependent parameters [threshold (dB), steepness]
    mcs_params = [
        -6.7, 1.2;   % MCS 0 (QPSK)
        -5.0, 1.3;   % MCS 1 (QPSK)
        -3.2, 1.4;   % MCS 2 (QPSK)
        -1.5, 1.5;   % MCS 3 (QPSK)
         0.8, 1.6;   % MCS 4 (16-QAM)
         2.0, 1.8;   % MCS 5 (16-QAM)
         4.5, 1.9;   % MCS 6 (16-QAM)
         6.8, 2.0;   % MCS 7 (16-QAM)
         9.2, 2.1;   % MCS 8 (64-QAM)
        11.5, 2.2;   % MCS 9 (64-QAM)
        14.0, 2.3;   % MCS 10 (64-QAM)
        16.3, 2.4;   % MCS 11 (64-QAM)
        18.7, 2.5;   % MCS 12 (256-QAM)
        20.5, 2.6;   % MCS 13 (256-QAM)
        21.8, 2.7;   % MCS 14 (256-QAM)
    ];
 
    % Get parameters for the specified MCS
    threshold = mcs_params(mcs+1, 1);  % +1 because MATLAB indexing starts at 1
%     steepness = mcs_params(mcs+1, 2);
    steepness=0.2;
    
    % Sigmoid-based BLER calculation
    BLER = 1 ./ (1 + exp(-steepness * (threshold - sinr)));
    BLER = max(0, min(1, BLER));
end



