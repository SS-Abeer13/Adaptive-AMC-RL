function [SINR, uePos] = calculateControlledSINR_N(simTime, fc, hBS, txPower, BW, numUsers, bsPos)
% Generic-N variant of calculateControlledSINR2.
%   SINR : simTime x numUsers
%   uePos: simTime x 2 x numUsers

    trajectories = cell(1, numUsers);
    [trajectories{:}] = randomWaypointSimulation(numUsers, simTime);

    SINR  = zeros(simTime, numUsers);
    uePos = zeros(simTime, 2, numUsers);
    for i = 1:numUsers
        uePos(:,:,i) = trajectories{i};
        SINR(:, i)   = computeSINR(trajectories{i}, fc, txPower, BW, bsPos);
    end
end
