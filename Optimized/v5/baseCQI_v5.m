function cqi = baseCQI_v5(obs_SINR_dB, env)
% baseCQI_v5  Fixed-mapping CQI from an observed SINR (vectorized over users).
%   This is the baseline's decision and the reference point for the v5
%   baseline-relative action: sent_CQI = clip(baseCQI + offset).
    cqi = zeros(size(obs_SINR_dB));
    for j = 1:numel(obs_SINR_dB)
        q = find(obs_SINR_dB(j) >= env.CQI_thresholds, 1, 'last');
        if isempty(q), q = env.min_CQI; end
        cqi(j) = max(env.min_CQI, min(env.max_CQI, q));
    end
end
