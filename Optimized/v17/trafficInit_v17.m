function Q = trafficInit_v17(env, N, countFrom)
% trafficInit_v17  Deadline-traffic queue state with RTT process tracking.
    if nargin < 3, countFrom = 0; end
    Q.on  = isfield(env, 'traffic') && strcmpi(env.traffic, 'deadline');
    Q.has = true(1, N);
    if Q.on, Q.has = false(1, N); end
    Q.rem    = zeros(1, N); % Remaining useful bits to be ACKed
    % B2 fix (PLAN_v17.md): full-buffer traffic (~Q.on) has no packet-arrival
    % step to (re-)stock Q.tx_rem (trafficPre_v17 returns immediately when
    % ~Q.on), so it stayed 0 forever -- the RTT eligibility check
    % `hasFree = ... & (Q.tx_rem > 0)` in DeepA2C/evalPolicy/DeepPPO_v17 was
    % always false for full-buffer users, so no new transmission was ever
    % scheduled under harq_rtt > 0. Full buffer means data is always
    % available; Q.tx_rem is only ever decremented/incremented when Q.on
    % (harqTransmit_v17/harqFeedback_v17, both gated on Q.on), so a
    % positive constant here stays positive for the life of the episode.
    if Q.on, Q.tx_rem = zeros(1, N); else, Q.tx_rem = ones(1, N); end
    Q.dl     = zeros(1, N);
    Q.arr    = zeros(1, N);
    Q.ph     = 0; if Q.on, Q.ph = mod(7 * (1:N), env.pkt_period); end
    Q.okU    = zeros(1, N);
    Q.resU   = zeros(1, N);
    Q.countFrom = countFrom;
end
