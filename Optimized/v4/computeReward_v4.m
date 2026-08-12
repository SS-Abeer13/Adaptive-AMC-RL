function r = computeReward_v4(BLER, TBS_bits, env)
% computeReward_v4  Unified, normalized reward (audit fix C4).
%   r = (1 - BLER) * TBS * 1e-3 / env.reward_scale     ('throughput')
%   Identical for ALL learners. No imitation bonus, no no-op shaping, no
%   per-algorithm scaling. Unscheduled TTIs earn 0 (the true goodput).
%
%   'bler_target' mode kept for ablations: normalized TBS if BLER <= 0.1,
%   else -10/scale.

    switch lower(env.reward_mode)
        case 'throughput'
            r = (1 - BLER) * TBS_bits * 1e-3 / env.reward_scale;
        case 'bler_target'
            if BLER <= 0.1
                r = TBS_bits * 1e-3 / env.reward_scale;
            else
                r = -10 / env.reward_scale;
            end
        otherwise
            error('computeReward_v4: unknown mode "%s"', env.reward_mode);
    end
end
