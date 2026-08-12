function SINR_dB = computeSINR(Uepos, fc, txPower, BW, bsPos)
    c = 3e8; k = 1.38e-23; T = 290;
    N = size(Uepos,1);

    % distance from BS (centered)
    d2D = vecnorm(Uepos - bsPos, 2, 2);
    d2D(d2D < 1) = 1;

    % 3GPP UMa NLOS path loss (meters, fc in GHz)
    pathLoss_dB = 28 + 50*log10(d2D) + 20*log10(fc/1e9);

    % lognormal shadowing + smoothed Rayleigh
    shadowing_dB = 0.9*randn(N,1);
    fading_linear = (raylrnd(1,N,1)).^2;
    fading_dB = 10*log10(movmean(fading_linear, 200));

    totalLoss_dB = pathLoss_dB + shadowing_dB - fading_dB;

    tx_W = 10^((txPower-30)/10);
    rx_W = tx_W ./ 10.^(totalLoss_dB/10);
    noise_W = k*T*BW;

    SINR_dB = 10*log10(rx_W./noise_W);
end