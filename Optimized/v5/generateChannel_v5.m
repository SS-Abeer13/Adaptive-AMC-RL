function [SINR_dB, dist, uePos] = generateChannel_v5(simTime, env)
% generateChannel_v5  Citable channel generator (TR 38.901 UMa NLOS).
%   Identical model to optimized/v4, supports arbitrary env.N.
%   [SINR_dB, dist, uePos] = generateChannel_v5(simTime, env)
%     SINR_dB : simTime x N effective SINR (dB)
%     dist    : simTime x N 2-D BS-UE distance (m)
%     uePos   : simTime x 2 x N positions (m)
%
%   Path loss: PL = 13.54 + 39.08 log10(d3D) + 20 log10(fc_GHz) - 0.6(hUE-1.5)
%   Shadowing: log-normal sigma dB, Gudmundson spatial correlation.
%   Fast fading: unit-power complex Gaussian AR(1) per interval.
%   Noise: kTB + NF; link budget includes gain, O2I and interference margin.
%   No clipping; no rendering (the v3 5-hour runtime was the RWP animation).

    N = env.N;
    uePos = zeros(simTime, 2, N);
    switch lower(env.mobility)
        case 'radial'
            d = linspace(env.d0, env.cellRadius, simTime).';
            for i = 1:N
                ang = 2*pi*(i-1)/max(N,1);
                uePos(:, 1, i) = env.bsPos(1) + d*cos(ang);
                uePos(:, 2, i) = env.bsPos(2) + d*sin(ang);
            end
        case 'rwp'
            for i = 1:N
                pos  = env.areaSize * rand(1, 2);
                dest = env.areaSize * rand(1, 2);
                for t = 1:simTime
                    dir = dest - pos; L = norm(dir);
                    if L < env.speed
                        pos = dest; dest = env.areaSize * rand(1, 2);
                    else
                        pos = pos + env.speed * dir / L;
                    end
                    uePos(t, :, i) = pos;
                end
            end
        otherwise
            error('generateChannel_v5: unknown mobility "%s"', env.mobility);
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
            rho = exp(-step_d(t) / env.d_corr);
            SF(t) = rho*SF(t-1) + env.sigma_SF*sqrt(1 - rho^2)*randn;
        end

        h = zeros(simTime, 1); h(1) = (randn + 1i*randn)/sqrt(2);
        rf = env.rho_fading;
        for t = 2:simTime
            h(t) = rf*h(t-1) + sqrt(1 - rf^2)*(randn + 1i*randn)/sqrt(2);
        end
        fad_dB = 10*log10(abs(h).^2 + 1e-12);

        rx_dBm = env.txPower_dBm + env.G_dBi - PL - SF + fad_dB - env.O2I_dB;
        SINR_dB(:, i) = rx_dBm - noise_dBm - env.IM_dB;
    end
end
