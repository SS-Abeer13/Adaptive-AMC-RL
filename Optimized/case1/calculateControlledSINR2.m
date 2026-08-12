function [SINR, uePos] = calculateControlledSINR2(simTime, cellRadius, fc, hBS, hUE, txPower, BW)
    % Constants
    c = 3e8; % Speed of light (m/s)
    N0 = -174; % dBm/Hz
    noisePower = 10^((N0 + 10*log10(BW))/10);
    
    % Antenna parameters
    antennaGain = 10; % dBi
    wallLoss = 0; % dB
    
    % Mobility parameters (more deterministic movement)
    radialSpeed = cellRadius/simTime; % Ensures reach cell edge in simTime
    uePos = zeros(simTime, 2);
    for t = 1:simTime
        uePos(t,:) = [t*radialSpeed, 0]; % Radial outward movement
    end
    
    % Channel parameters (constrained)
    sigma_shadow = 4; % Reduced shadowing
    correlationDistance = 100; % Longer correlation
    K_factor = 6; % Stronger LOS component
    
    % Correlated shadowing with bounded range
    shadowing = sigma_shadow * filter(1, [1 -exp(-1/correlationDistance)], randn(simTime,1));
    shadowing = min(max(shadowing, -8), 8); % Bound to ±8dB
    
    % Rician channel with controlled Doppler
    fd = (radialSpeed*fc/c); % Doppler frequency
    ricChan = comm.RicianChannel(...
        'SampleRate', 1e3,...
        'KFactor', K_factor,...
        'MaximumDopplerShift', fd,...
        'PathDelays', [0],...
        'AveragePathGains', [0]);
    
    % Main loop
    SINR = zeros(simTime, 1);
    basePathLoss = zeros(simTime, 1);
    
    for t = 1:simTime
        % Calculate distance-dependent path loss
        dist_km = norm(uePos(t,:))/1000;
        L = 46.3 + 33.9*log10(fc/1e6) - 13.82*log10(hBS) + ...
            (44.9 - 6.55*log10(hBS)) * log10(dist_km + eps) + 3;
        L=max(L,80);
        basePathLoss(t) = L;
        
        % Controlled received power
        rxPower = txPower + antennaGain- L - wallLoss - shadowing(t);
        rxPowerLin = 10^(rxPower/10)/1000;
        
        % Generate constrained fading
        fading = ricChan(1);
        constrainedFading = min(max(abs(fading), 0.5), 1.5); % Bound fading
        
        % Final SINR with limits
        SINR(t) = 10*log10((constrainedFading^2 * rxPowerLin) / noisePower);
        
    end
end


