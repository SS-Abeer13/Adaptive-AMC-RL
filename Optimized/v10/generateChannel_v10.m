function [SINR_dB, dist, meta] = generateChannel_v10(simTime, env, metaFix)
% generateChannel_v10  v7 channel generator: heterogeneous users, Jakes
% fading, interference bursts, mid-trace speed changes.
    if nargin < 3, metaFix = []; end
    N = env.N;

    if ~isempty(metaFix)
        delays   = metaFix.delays;
        baseSpd  = metaFix.baseSpeed;
        spd2     = metaFix.speed2;
        switchT  = min(metaFix.switchT, simTime);
    else
        h = max(0, min(1, env.hetero));
        if h == 0
            delays  = env.delay_hom * ones(1, N);
            baseSpd = env.speed * ones(1, N);
        else
            ds = env.delay_set;
            mid = env.delay_hom;
            lo  = round(mid - h*(mid - min(ds)));  hi = round(mid + h*(max(ds) - mid));
            delays = lo + randi(hi - lo + 1, 1, N) - 1;
            baseSpd = env.speed_min + h*(env.speed_max - env.speed_min)*rand(1, N);
        end
        spd2 = baseSpd;
        switchT = (simTime+1) * ones(1, N);
        if isfield(env,'speed_switch') && env.speed_switch
            for i = 1:N
                if rand < 0.5
                    switchT(i) = round(simTime*(0.3 + 0.4*rand));
                    if h == 0, spd2(i) = baseSpd(i);
                    else, spd2(i) = env.speed_min + h*(env.speed_max - env.speed_min)*rand;
                    end
                end
            end
        end
    end

    speeds = zeros(simTime, N);
    for i = 1:N
        speeds(:, i) = baseSpd(i);
        if switchT(i) <= simTime
            speeds(switchT(i):end, i) = spd2(i);
        end
    end

    % Jakes AR(1) coefficient per user per TTI
    if isfield(env,'jakes') && env.jakes
        fd  = speeds * env.fc / 3e8;
        rho = besselj(0, 2*pi*fd*env.T_tti);
        rho = max(0, min(0.9999, rho));
    else
        rho = env.rho_fading * ones(simTime, N);
    end

    % Interference burst chain (cell-wide 2-state Markov)
    burst = false(simTime, 1);
    if isfield(env,'burst_on') && env.burst_on
        pEnter = 1/max(env.burst_dwell_calm, 1);
        pExit  = 1/max(env.burst_dwell_burst, 1);
        b = false;
        for t = 1:simTime
            if b, if rand < pExit,  b = false; end
            else, if rand < pEnter, b = true;  end
            end
            burst(t) = b;
        end
    end
    Iextra = double(burst) * env.burst_IM_dB;

    % Mobility (RWP) + link budget
    uePos = zeros(simTime, 2, N);
    for i = 1:N
        pos  = env.areaSize * rand(1, 2);
        dest = env.areaSize * rand(1, 2);
        for t = 1:simTime
            % v9 FIX: displacement per TTI = v * T_tti * mob_kappa (m).
            % v7/v8 used v metres per TTI (mob_kappa = 1000).
            kap = 1; if isfield(env, 'mob_kappa'), kap = env.mob_kappa; end
            stp = speeds(t, i) * env.T_tti * kap;
            dir = dest - pos; L = norm(dir);
            if L < stp, pos = dest; dest = env.areaSize * rand(1, 2);
            else,       pos = pos + stp * dir / L;
            end
            uePos(t, :, i) = pos;
        end
    end

    SINR_dB = zeros(simTime, N);
    dist    = zeros(simTime, N);
    noise_dBm = -174 + 10*log10(env.BW) + env.NF_dB;

    for i = 1:N
        d2D = sqrt((uePos(:,1,i) - env.bsPos(1)).^2 + (uePos(:,2,i) - env.bsPos(2)).^2);
        d2D = max(d2D, 10);
        dist(:, i) = d2D;
        d3D = sqrt(d2D.^2 + (env.hBS - env.hUE)^2);
        PL = 13.54 + 39.08*log10(d3D) + 20*log10(env.fc/1e9) - 0.6*(env.hUE - 1.5);

        SF = zeros(simTime, 1); SF(1) = env.sigma_SF * randn;
        step_d = [0; sqrt(sum(diff(squeeze(uePos(:,:,i))).^2, 2))];
        for t = 2:simTime
            r = exp(-step_d(t) / env.d_corr);
            SF(t) = r*SF(t-1) + env.sigma_SF*sqrt(1 - r^2)*randn;
        end

        h = zeros(simTime, 1); h(1) = (randn + 1i*randn)/sqrt(2);
        for t = 2:simTime
            rf = rho(t, i);
            h(t) = rf*h(t-1) + sqrt(1 - rf^2)*(randn + 1i*randn)/sqrt(2);
        end
        fad_dB = 10*log10(abs(h).^2 + 1e-12);

        rx_dBm = env.txPower_dBm + env.G_dBi - PL - SF + fad_dB - env.O2I_dB;
        SINR_dB(:, i) = rx_dBm - noise_dBm - env.IM_dB - Iextra;
    end

    meta = struct('delays', delays, 'speeds', speeds, 'rho', rho, ...
                  'burst', burst, 'baseSpeed', baseSpd, 'speed2', spd2, ...
                  'switchT', switchT);
end
