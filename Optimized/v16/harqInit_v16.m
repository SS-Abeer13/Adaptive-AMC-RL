function H = harqInit_v16(N, env)
% harqInit_v16  Initializes per-user multi-process HARQ tracker (PLAN_v16 A1-A2).
% Tracks per-user and per-process in-flight transmissions and retransmissions.
    if nargin < 2 || isempty(env)
        nproc = 1;
        rtt   = 0;
    else
        nproc = 1; if isfield(env, 'harq_nproc') && ~isempty(env.harq_nproc), nproc = env.harq_nproc; end
        rtt   = 0; if isfield(env, 'harq_rtt')   && ~isempty(env.harq_rtt),   rtt   = env.harq_rtt;   end
    end

    % Base scalar fields per user (for backward compatibility & instantaneous path)
    H = struct('pend',     false(1, N), ...
               'nret',     zeros(1, N), ...
               'tbs',      zeros(1, N), ...
               'mcs',      zeros(1, N), ...
               'sinr_eff', zeros(1, N), ...
               'nproc',    nproc, ...
               'rtt',      rtt);

    % Multi-process matrices (N x nproc)
    H.proc_busy    = false(N, nproc);
    H.proc_ready_t = zeros(N, nproc);
    H.proc_isRetx  = false(N, nproc);
    H.proc_nret    = zeros(N, nproc);
    H.proc_mcs     = zeros(N, nproc);
    H.proc_tbs     = zeros(N, nproc);
    H.proc_bits    = zeros(N, nproc);
    H.proc_ok      = false(N, nproc);
    H.proc_dec_id  = zeros(N, nproc);
end
