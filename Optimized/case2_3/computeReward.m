function r = computeReward(BLER, TBS, mode)
% Reward function for RL-AMC. Modes from Mota 2019:
%   'throughput' | 'se'  -> r = (1-BLER) * TBS * 1e-3            (Mbps)
%   'bler_target'        -> r = TBS * 1e-3 if BLER<=0.1, else -10

    BLER_target = 0.1;
    penalty     = -10;

    switch lower(mode)
        case {'throughput', 'se'}
            r = (1 - BLER) * TBS * 1e-3;
        case {'bler_target', 'bler'}
            if BLER <= BLER_target
                r = TBS * 1e-3;
            else
                r = penalty;
            end
        otherwise
            error('computeReward: unknown mode "%s".', mode);
    end
end
