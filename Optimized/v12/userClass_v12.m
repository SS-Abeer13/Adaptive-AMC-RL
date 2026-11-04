function [dc, vc] = userClass_v12(delay, speed)
% userClass_v12  Maps user feedback delay and velocity to discrete class bins.
% Partition:
%   dc: 1 = delay <= 4 TTIs, 2 = delay >= 5 TTIs
%   vc: 1 = < 10 m/s (pedestrian), 2 = 10-20 m/s (urban vehicular), 3 = > 20 m/s (highway)
    dc = 1 + (delay >= 5);
    vc = 1 + (speed >= 10) + (speed > 20);
end
