function [obs_SINR, obs_CQI] = cqiFeedback_v4(SINR_dB, env)
% cqiFeedback_v4  Imperfect CQI reporting chain (audit fix C2).
%   The agent/baseline never sees the true instantaneous SINR. It sees the
%   SINR measured env.cqi_delay scheduling intervals ago, corrupted by
%   N(0, env.sigma_meas^2) dB estimation noise, and the CQI obtained by
%   quantizing that observation with the 3GPP threshold map.
%
%   obs_SINR : T x N delayed + noisy SINR (dB)   -- agent state feature
%   obs_CQI  : T x N quantized CQI in 1..15      -- baseline input / state

    [T, N] = size(SINR_dB);
    idx = max((1:T).' - env.cqi_delay, 1);
    obs_SINR = SINR_dB(idx, :) + env.sigma_meas * randn(T, N);

    obs_CQI = zeros(T, N);
    for i = 1:N
        for t = 1:T
            q = find(obs_SINR(t, i) >= env.CQI_thresholds, 1, 'last');
            obs_CQI(t, i) = max(1, min(15, q));
        end
    end
end
