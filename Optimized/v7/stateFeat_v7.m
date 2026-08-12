function S = stateFeat_v7(tier, ref, dRef, obs, dS, off, slope4, nk, H, spd, burstObs, ctx)
% stateFeat_v7  Deep-agent feature vector, Tier A (info-equal) or Tier B (full state).
    base = [ref/15; dRef/5; obs/30; dS/5; off/5];
    if upper(tier) == 'A'
        S = single([base; ctx]);
    else
        extra = [slope4/5; nk; double(H.pend); H.nret/3; spd/30; burstObs];
        S = single([base; extra; ctx]);
    end
end
