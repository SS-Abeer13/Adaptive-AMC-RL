function cqi = baseCQI_v17(obs_SINR_dB, env)
% baseCQI_v17  Fixed-mapping CQI from an observed SINR (vectorized over users).
% Drop-in, bit-identical replacement for baseCQI_v5: uses discretize instead
% of a per-element find() loop (P0.2 vectorisation).
%   This is the baseline's decision and the reference point for the
% baseline-relative action: sent_CQI = clip(baseCQI + offset).
    edges = [env.CQI_thresholds(:).', Inf];
    q = discretize(obs_SINR_dB, edges);
    q(isnan(q)) = env.min_CQI;
    cqi = max(env.min_CQI, min(env.max_CQI, q));
end
