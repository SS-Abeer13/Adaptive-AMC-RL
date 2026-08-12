function r = computeReward_v5(BLER, TBS_bits, env)
% computeReward_v5  Unified normalized reward (audit fix C4). Identical for
% all learners; unscheduled TTIs earn 0 (true goodput). No imitation bonus.
    switch lower(env.reward_mode)
        case 'throughput'
            r = (1 - BLER) * TBS_bits * 1e-3 / env.reward_scale;
        case 'bler_target'
            if BLER <= 0.1, r = TBS_bits * 1e-3 / env.reward_scale;
            else,           r = -10 / env.reward_scale; end
        otherwise
            error('computeReward_v5: unknown mode "%s"', env.reward_mode);
    end
end
