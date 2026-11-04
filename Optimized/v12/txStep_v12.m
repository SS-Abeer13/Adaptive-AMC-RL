function [tp, off, H, bler1, nackEv, dropEv] = txStep_v12(sent, Strue_row, rb, off, H, env, u, targ)
% v9: optional u (1 x N uniforms) gives common random numbers across schemes;
% without it the global stream is used (training).
% P1: optional targ (scalar, or 1 x N per-user target BLER) overrides
% env.olla_target for the OLLA up-step size, so a per-user, possibly
% time-varying target (README_v12.md P1: target-BLER action space, the
% per-class tuned-target comparator, the contextual target bandit) all go
% through the same physics. Omitted/empty -> env.olla_target for everyone,
% i.e. bit-for-bit the v10/v12-P0 behaviour (test_equivalence_v12.m).
% txStep_v12  v8 transmission physics: HARQ Chase combining, outer-loop tracking,
% and unconstrained retransmission accounting.
%
% P0.2: vectorised over the active (rb > 0) users instead of a per-user
% for-loop. When u is empty, the active users' outcome draws are taken as
% one rand(1, numel(idx)) call, in the same ascending-index order as the
% original per-user loop, so the global RNG stream is consumed identically
% and results are bit-for-bit unchanged (see test_equivalence_v12.m).
%
% Outputs:
%   tp     : Delivered throughput in Mbps per user (scaled from TBS)
%   off    : Updated OLLA offsets per user
%   H      : Updated HARQ state structure
%   bler1  : First-transmission BLER (NaN if not a first transmission)
%   nackEv : Logical array indicating NACK event at this TTI
%   dropEv : Logical array indicating dropped packet event (exceeded max retx)
    N = numel(sent);
    tp = zeros(1, N);
    bler1 = nan(1, N);
    nackEv = false(1, N);
    dropEv = false(1, N);

    if nargin < 8 || isempty(targ), targ = env.olla_target; end
    if isscalar(targ), targ = targ * ones(1, N); end
    du = env.olla_step_down * targ ./ (1 - targ);  % P1: 1 x N, per-user up-step
    dd = env.olla_step_down;

    if nargin < 7, u = []; end

    idx = find(rb > 0);
    if isempty(idx), return; end

    if isempty(u)
        ui = rand(1, numel(idx));
    else
        ui = u(idx);
    end

    isRetx  = env.harq_on && any(H.pend);
    retxSel = false(1, numel(idx));
    if isRetx, retxSel = H.pend(idx); end
    retxIdx = idx(retxSel);
    newIdx  = idx(~retxSel);
    uiRetx  = ui(retxSel);
    uiNew   = ui(~retxSel);

    % ------------------------------------------------------------------
    % HARQ retransmissions with Chase combining
    % ------------------------------------------------------------------
    if ~isempty(retxIdx)
        effS = Strue_row(retxIdx) + env.harq_comb_dB * H.nret(retxIdx);
        bl = estimateBLER_v12(effS, H.mcs(retxIdx));
        ack = uiRetx > bl;

        ackIdx  = retxIdx(ack);
        nackIdx = retxIdx(~ack);

        tp(ackIdx)     = H.tbs(ackIdx) * 1e-3;
        H.pend(ackIdx) = false;
        H.nret(ackIdx) = 0;
        off(ackIdx)    = off(ackIdx) + 0.5 * du(ackIdx);

        nackEv(nackIdx) = true;
        H.nret(nackIdx) = H.nret(nackIdx) + 1;
        dropSel = H.nret(nackIdx) > env.harq_max_retx;
        dropIdx = nackIdx(dropSel);
        keepIdx = nackIdx(~dropSel);

        dropEv(dropIdx) = true;
        H.pend(dropIdx) = false;
        H.nret(dropIdx) = 0;
        off(dropIdx)    = off(dropIdx) - dd;

        off(keepIdx) = off(keepIdx) - 0.5 * dd;
    end

    % ------------------------------------------------------------------
    % Initial transmissions (new transport blocks)
    % ------------------------------------------------------------------
    if ~isempty(newIdx)
        mcs = max(0, min(14, sent(newIdx) - 1));
        bl = estimateBLER_v12(Strue_row(newIdx), mcs);
        bler1(newIdx) = bl;
        TBS = tbsFromMCSandRB_v12(mcs, rb(newIdx));
        ack = uiNew > bl;

        ackIdx  = newIdx(ack);
        nackIdx = newIdx(~ack);

        tp(ackIdx)  = TBS(ack) * 1e-3;
        off(ackIdx) = off(ackIdx) + du(ackIdx);

        nackEv(nackIdx) = true;
        off(nackIdx)    = off(nackIdx) - dd;
        if env.harq_on
            H.pend(nackIdx) = true;
            H.nret(nackIdx) = 1;
            H.tbs(nackIdx)  = TBS(~ack);
            H.mcs(nackIdx)  = mcs(~ack);
        else
            dropEv(nackIdx) = true;
        end
    end

    % Anti-windup bound on the OLLA offset (see defaultEnv_v12.olla_off_lim)
    if isfield(env, 'olla_off_lim') && ~isempty(env.olla_off_lim)
        off(idx) = max(-env.olla_off_lim, min(env.olla_off_lim, off(idx)));
    end
end
