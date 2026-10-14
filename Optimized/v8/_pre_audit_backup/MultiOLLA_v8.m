function [tp, offFast, offSlow, H, bler1, nackEv] = MultiOLLA_v8(sent, Strue_row, rb, offFast, offSlow, H, env, alpha)
% MultiOLLA_v8  Multi-Offset Outer Loop Link Adaptation (Ahsen et al., arXiv:2604.20459).
% Maintains dual integrators (fast tracking for bursts, slow for calm)
% and adaptively blends them based on detected channel regime.
    if nargin < 8 || isempty(alpha), alpha = 0.5 * ones(1, numel(sent)); end
    N = numel(sent);

    % Step dimensions: fast integrator responds 3x faster
    dd_slow = env.olla_step_down;
    du_slow = dd_slow * env.olla_target / (1 - env.olla_target);

    dd_fast = env.multi_olla_fast;
    du_fast = dd_fast * env.olla_target / (1 - env.olla_target);

    % Blended effective offset
    off_eff = alpha .* offFast + (1 - alpha) .* offSlow;

    % Execute transmission
    [tp, ~, H, bler1, nackEv] = txStep_v8(sent, Strue_row, rb, off_eff, H, env);

    % Update dual integrators based on transmission feedback
    for i = 1:N
        if rb(i) <= 0, continue; end
        if nackEv(i)
            offSlow(i) = offSlow(i) - dd_slow;
            offFast(i) = offFast(i) - dd_fast;
        else
            offSlow(i) = offSlow(i) + du_slow;
            offFast(i) = offFast(i) + du_fast;
        end
    end
end
