function [obs_SINR, obs_CQI] = cqiFeedback_v8(SINR_dB, env, delays)
% cqiFeedback_v8  Per-user delayed, noisy CQI feedback model.
% Applies user-specific reporting delay d_i in [2, 8] TTIs and Gaussian
% reporting noise sigma_meas = 1.0 dB before 15-level 3GPP quantization.
    [T, N] = size(SINR_dB);
    if nargin < 3 || isempty(delays), delays = env.cqi_delay * ones(1, N); end

    obs_SINR = zeros(T, N);
    for i = 1:N
        idx = max((1:T).' - delays(i), 1);
        obs_SINR(:, i) = SINR_dB(idx, i);
    end
    obs_SINR = obs_SINR + env.sigma_meas * randn(T, N);

    if nargout > 1
        obs_CQI = zeros(T, N);
        for i = 1:N
            for t = 1:T
                q = find(obs_SINR(t, i) >= env.CQI_thresholds, 1, 'last');
                if isempty(q), q = 1; end
                obs_CQI(t, i) = max(1, min(15, q));
            end
        end
    end
end
