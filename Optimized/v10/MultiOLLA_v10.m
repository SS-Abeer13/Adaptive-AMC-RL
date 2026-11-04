function [tp, offFast, offSlow, H, bler1, nackEv] = MultiOLLA_v10(sent, Strue_row, rb, offFast, offSlow, H, env, alpha, u)
% MultiOLLA_v10  Multi-Offset Outer Loop Link Adaptation (Ahsen et al., arXiv:2604.20459).
% Maintains dual integrators (fast tracking for bursts, slow for calm)
% and adaptively blends them based on detected channel regime.
    if nargin < 8 || isempty(alpha), alpha = 0.5 * ones(1, numel(sent)); end
    if nargin < 9, u = []; end
    N = numel(sent);

    % Step dimensions. AUDIT FIX: the slow loop previously used
    % env.olla_step_down (0.5 dB) and ignored env.multi_olla_slow (0.2 dB),
    % so the "slow" loop was just standard OLLA. Fast/slow = 0.8/0.2 dB (4x).
    dd_slow = env.multi_olla_slow;
    du_slow = dd_slow * env.olla_target / (1 - env.olla_target);

    dd_fast = env.multi_olla_fast;
    du_fast = dd_fast * env.olla_target / (1 - env.olla_target);

    % Blended effective offset
    off_eff = alpha .* offFast + (1 - alpha) .* offSlow;

    % Execute transmission
    [tp, ~, H, bler1, nackEv] = txStep_v10(sent, Strue_row, rb, off_eff, H, env, u);

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
        if isfield(env, 'olla_off_lim') && ~isempty(env.olla_off_lim)
            offSlow(i) = max(-env.olla_off_lim, min(env.olla_off_lim, offSlow(i)));
            offFast(i) = max(-env.olla_off_lim, min(env.olla_off_lim, offFast(i)));
        end
    end
end
