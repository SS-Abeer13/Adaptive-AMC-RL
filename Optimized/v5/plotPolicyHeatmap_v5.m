function plotPolicyHeatmap_v5(policy, ptype, env)
% plotPolicyHeatmap_v5  Explainability figure for the baseline-relative policy.
%   Shows the learned greedy OFFSET as a function of (observed SINR, baseline
%   CQI) at d_base = 0, flat trend. Because action 0 == baseline, any nonzero
%   structure is exactly the learned correction to the delayed/noisy CQI.
%   Right panel: offset for rising vs falling trend at fixed mid CQI -- the
%   compensation the trend feature enables.

    sinr_g = -10:0.5:30; cqi_g = 1:15;
    Ag = numel(sinr_g); Bg = numel(cqi_g);
    A = env.actions; no_op = find(A==0); maxD = env.max_delta;
    learned = zeros(Bg, Ag);
    onGPU = strcmpi(ptype,'a2c') && isa(extractdata(policy.Learnables.Value{1}),'gpuArray');
    [sc, sOneHot] = schedContext_v5(env.scheduler, env);   % visualize primary regime
    ctxRow = repmat(single(sOneHot), 1, Ag);

    for b = 1:Bg
        cqi = cqi_g(b);
        if strcmpi(ptype,'a2c')
            S = single([repmat(cqi/15,1,Ag); zeros(1,Ag); sinr_g/30; zeros(1,Ag); ctxRow]);
            if onGPU, S = gpuArray(S); end
            logits = gather(extractdata(predict(policy, dlarray(S,'CB'))));
            [~, ai] = max(logits, [], 1); learned(b,:) = A(ai);
        else
            for a = 1:Ag
                [~, sb] = min(abs(env.SINR_bins - sinr_g(a)));
                tab = squeeze(policy(cqi, maxD+1, sb, 2, sc, :));   % flat trend
                learned(b,a) = A(argmaxNoOp_v5(tab, no_op));
            end
        end
    end

    % trend sensitivity at mid CQI (=8)
    cqi0 = 8; off_tr = zeros(3, Ag);
    for tb = 1:3
        if strcmpi(ptype,'a2c')
            dsv = [-2 0 2]; dsv = dsv(tb);
            S = single([repmat(cqi0/15,1,Ag); zeros(1,Ag); sinr_g/30; repmat(dsv/5,1,Ag); ctxRow]);
            if onGPU, S = gpuArray(S); end
            logits = gather(extractdata(predict(policy, dlarray(S,'CB'))));
            [~, ai] = max(logits, [], 1); off_tr(tb,:) = A(ai);
        else
            for a = 1:Ag
                [~, sb] = min(abs(env.SINR_bins - sinr_g(a)));
                tab = squeeze(policy(cqi0, maxD+1, sb, tb, sc, :));
                off_tr(tb,a) = A(argmaxNoOp_v5(tab, no_op));
            end
        end
    end

    figure('Position',[60 60 1250 380],'Name',sprintf('v5 policy explainability (%s)', upper(env.scheduler)));
    subplot(1,2,1);
    imagesc(sinr_g, cqi_g, learned); axis xy; colormap(parula); colorbar; caxis([-2 2]);
    xlabel('Observed SINR (dB)'); ylabel('Baseline CQI');
    title('Learned offset vs baseline (flat trend)');
    subplot(1,2,2); hold on; grid on;
    plot(sinr_g, off_tr(1,:), 'b', 'LineWidth',1.5);
    plot(sinr_g, off_tr(2,:), 'k', 'LineWidth',1.5);
    plot(sinr_g, off_tr(3,:), 'r', 'LineWidth',1.5);
    xlabel('Observed SINR (dB)'); ylabel('Chosen offset'); ylim([-2.2 2.2]);
    legend({'falling','flat','rising'}, 'Location','best');
    title(sprintf('Trend compensation (baseline CQI=%d)', cqi0));
    sgtitle(sprintf('Baseline-relative policy (%s)  |  scheduler=%s', upper(ptype), upper(env.scheduler)));
end
