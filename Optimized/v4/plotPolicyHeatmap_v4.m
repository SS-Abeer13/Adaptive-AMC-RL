function plotPolicyHeatmap_v4(policy, ptype, env)
% plotPolicyHeatmap_v4  Explainability figure (audit section 4):
%   left   - learned greedy CQI offset over (observed SINR, current CQI),
%            at delta_CQI = 0
%   middle - reference offset clip(CQI_map(obs SINR) - CQI, -2..+2), i.e.
%            what a fixed-mapping controller would do with the same input
%   right  - difference (where and how the policy deviates from the mapping;
%            structure here = learned delay/noise compensation)
%
%   ptype: 'a2c' (dlnetwork), 'ac' (theta), 'ql' (Q-table)

    sinr_g = -10:0.5:30;
    cqi_g  = 1:15;
    A = numel(sinr_g); B = numel(cqi_g);
    learned = zeros(B, A); ref = zeros(B, A);
    actions = env.actions;
    maxD = env.max_delta;

    onGPU = false;
    if strcmpi(ptype, 'a2c')
        onGPU = isa(extractdata(policy.Learnables.Value{1}), 'gpuArray');
    end

    for b = 1:B
        cqi = cqi_g(b);
        switch lower(ptype)
            case 'a2c'
                % v4.1: 4 features, trend = 0 (flat) at dCQI = 0
                S = single([repmat(cqi/15, 1, A); zeros(1, A); ...
                            sinr_g/30; zeros(1, A)]);
                if onGPU, S = gpuArray(S); end
                logits = gather(extractdata(predict(policy, dlarray(S, 'CB'))));
                [~, ai] = max(logits, [], 1);
                learned(b, :) = actions(ai);
            case {'ac', 'ql'}
                no_op = find(actions == 0);
                for a = 1:A
                    [~, sb] = min(abs(env.SINR_bins - sinr_g(a)));
                    tab = squeeze(policy(cqi, maxD+1, sb, 2, :, 1)); % flat trend
                    ai = argmaxNoOp_v4(tab, no_op);
                    learned(b, a) = actions(ai);
                end
            otherwise
                error('plotPolicyHeatmap_v4: unsupported ptype "%s"', ptype);
        end
        for a = 1:A
            q = find(sinr_g(a) >= env.CQI_thresholds, 1, 'last');
            q = max(1, min(15, q));
            ref(b, a) = max(-2, min(2, q - cqi));
        end
    end

    figure('Position', [60 60 1250 380], 'Name', 'v4 policy heatmap');
    titles = {'Learned greedy offset', 'Fixed-mapping offset', 'Learned - mapping'};
    data = {learned, ref, learned - ref};
    for p = 1:3
        subplot(1, 3, p);
        imagesc(sinr_g, cqi_g, data{p}); axis xy;
        colormap(parula); colorbar;
        if p < 3, caxis([-2 2]); else, caxis([-4 4]); end
        xlabel('Observed SINR (dB)'); ylabel('Current CQI');
        title(titles{p});
    end
    sgtitle(sprintf('Policy explainability (%s), \\DeltaCQI = 0', upper(ptype)));
end
