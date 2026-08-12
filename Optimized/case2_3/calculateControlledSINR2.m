function [S1,S2,S3,S4,S5,U1,U2,U3,U4,U5] = ...
    calculateControlledSINR2(simTime, fc, hBS, txPower, BW, numUsers, bsPos)
    [U1,U2,U3,U4,U5] = randomWaypointSimulation(numUsers, simTime);
    S1 = computeSINR(U1, fc, txPower, BW, bsPos);
    S2 = computeSINR(U2, fc, txPower, BW, bsPos);
    S3 = computeSINR(U3, fc, txPower, BW, bsPos);
    S4 = computeSINR(U4, fc, txPower, BW, bsPos);
    S5 = computeSINR(U5, fc, txPower, BW, bsPos);
end
