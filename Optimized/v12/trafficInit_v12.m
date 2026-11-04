function Q = trafficInit_v12(env, N, countFrom)
% trafficInit_v12  Deadline-traffic state. For env.traffic = 'full' every
% user always has data (v9 behaviour) and nothing is counted.
    if nargin < 3, countFrom = 0; end
    Q.on  = isfield(env, 'traffic') && strcmpi(env.traffic, 'deadline');
    Q.has = true(1, N);
    if Q.on, Q.has = false(1, N); end
    Q.rem = zeros(1, N); Q.dl = zeros(1, N); Q.arr = zeros(1, N);
    Q.ph  = 0; if Q.on, Q.ph = mod(7 * (1:N), env.pkt_period); end
    Q.okU = zeros(1, N); Q.resU = zeros(1, N);
    Q.countFrom = countFrom;
end
