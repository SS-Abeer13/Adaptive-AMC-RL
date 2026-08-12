function [TBS, selected_RB, selected_MCS] = selectTBSFromSINR(current_SINR)
    % Load the predefined TBS table (RB 1-110 x MCS 0-14)
    tbsTable = createTBS_Table();
    
    % 3GPP CQI to SINR thresholds (dB)
    requiredSINR = [-Inf, -6.7, -4.7, -2.3, 0.2, 2.4, 4.3, 5.9, 8.1, 10.3, ...
                   11.7, 14.1, 16.3, 18.7, 21.0, 22.7];
    
    % CQI to MCS mapping (0-14)
    CQI_MCS_map = 0:14;
    
    % Determine CQI from SINR (exact mapping)
    CQI = find(current_SINR >= requiredSINR, 1, 'last');
    if isempty(CQI) || CQI < 1
        CQI = 1;
    elseif CQI > 15
        CQI = 15;
    end
    
    % Select MCS based on CQI (exact mapping)
    selected_MCS = CQI_MCS_map(CQI);


    
   % Ultra-granular RB selection with 20 SINR thresholds
if current_SINR < -24
    selected_RB = randi([1 2]);      % Very deep fade
elseif current_SINR < -22
    selected_RB = randi([3 5]);
elseif current_SINR < -20
    selected_RB = randi([6 9]);
elseif current_SINR < -18
    selected_RB = randi([10 14]);
elseif current_SINR < -16
    selected_RB = randi([15 19]);
elseif current_SINR < -14
    selected_RB = randi([20 25]);
elseif current_SINR < -12
    selected_RB = randi([26 31]);
elseif current_SINR < -10
    selected_RB = randi([32 37]);
elseif current_SINR < -8
    selected_RB = randi([38 43]);
elseif current_SINR < -6
    selected_RB = randi([44 49]);
elseif current_SINR < -4
    selected_RB = randi([50 55]);
elseif current_SINR < -2
    selected_RB = randi([56 61]);
elseif current_SINR < 0
    selected_RB = randi([62 77]);

% Positive SINR (0 to 30 dB) — 33 RBs
elseif current_SINR < 5
    selected_RB = randi([78 83]);
elseif current_SINR < 10
    selected_RB = randi([84 89]);
elseif current_SINR < 15
    selected_RB = randi([90 95]);
elseif current_SINR < 22
    selected_RB = randi([96 102]);
elseif current_SINR < 30
    selected_RB = randi([103 108]);
else
    selected_RB = randi([109 110]);  % Peak SINR, max throughput
end

    
    % Ensure RB is within table limits (1-110)
    selected_RB = max(1, min(110, selected_RB));
    
    % Get exact TBS from the table (MCS 0-14 → rows 1-15)
    TBS = tbsTable(selected_MCS + 1, selected_RB);
end