function [obs_SINR, obs_CQI] = cqiFeedback_v5(SINR_dB, env)
% cqiFeedback_v5  Imperfect CQI reporting chain (audit fix C2).
%   The agent/baseline never sees the true instantaneous SINR; they see the
%   SINR measured env.cqi_delay intervals ago plus N(0,sigma_meas^2) dB noise,
%   and obs_CQI is its 3GPP quantization. obs_CQI(t,i) is exactly what the
%   fixed-mapping baseline transmits, and the v5 baseline-relative action is
%   an offset from it.

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
