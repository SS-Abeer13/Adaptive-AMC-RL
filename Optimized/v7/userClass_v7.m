function [dc, vc] = userClass_v7(delay, meanSpeed)
% userClass_v7  Map (delay, mean speed) to the FixedPU class grid.
%   dc: 1 = delay <= 4, 2 = delay >= 5
%   vc: 1 = < 10 m/s, 2 = 10-20 m/s, 3 = > 20 m/s
    dc = 1 + (delay >= 5);
    vc = 1 + (meanSpeed >= 10) + (meanSpeed > 20);
end
