function F = featExtra_v16(env, X)
% featExtra_v16  Extra observable state rows (nExtra x N), all gNB-side:
%   X.age (1xN TTIs since last report), X.dev (1xN dB), X.cn (scalar),
%   X.Q (traffic state), X.t (TTI), X.H (HARQ state).
%   PLAN_v16 A4: 'harqx' adds 3 rows:
%     1. busy processes / harq_nproc
%     2. retx-ready flag (1 if user has a retransmission ready)
%     3. bits in flight / pkt_bits (0 for full buffer)
    N = numel(X.age);
    F = zeros(nExtra_v16(env), N, 'single');
    if isempty(F), return; end
    r = 0;
    P = max(1, env.cqi_period);
    for k = 1:numel(env.feat_extra)
        switch lower(env.feat_extra{k})
            case 'age'
                r = r + 1; F(r, :) = X.age / P;
            case 'dev'
                r = r + 1; F(r, :) = max(-2, min(2, X.dev / 10));
            case 'cellnack'
                r = r + 1; F(r, :) = X.cn;
            case 'dline'
                r = r + 1; F(r, :) = userDeadline_v16(env, N) / max(env.pkt_deadline);
            case 'slack'
                [sl, has, rf] = slackOf_v16(env, X.Q, X.t);
                Dm = max(env.pkt_deadline);
                F(r+1, :) = min(sl, Dm) / Dm;
                F(r+2, :) = has;
                F(r+3, :) = rf;
                r = r + 3;
            case 'harqx'
                if isfield(X, 'H') && isfield(X.H, 'proc_busy')
                    busy_frac = sum(X.H.proc_busy, 2)' / max(1, X.H.nproc);
                    retx_ready = double(any(X.H.proc_isRetx, 2))';
                    in_flight = zeros(1, N);
                    for ii = 1:N
                        b_busy = X.H.proc_busy(ii, :);
                        if any(b_busy)
                            in_flight(ii) = sum(X.H.proc_bits(ii, b_busy));
                        end
                    end
                    if isfield(env, 'pkt_bits') && env.pkt_bits > 0 && isfield(X, 'Q') && X.Q.on
                        flight_frac = in_flight / env.pkt_bits;
                    else
                        flight_frac = zeros(1, N);
                    end
                elseif isfield(X, 'H')
                    busy_frac = double(X.H.pend);
                    retx_ready = double(X.H.pend);
                    flight_frac = zeros(1, N);
                else
                    busy_frac = zeros(1, N);
                    retx_ready = zeros(1, N);
                    flight_frac = zeros(1, N);
                end
                F(r+1, :) = busy_frac;
                F(r+2, :) = retx_ready;
                F(r+3, :) = flight_frac;
                r = r + 3;
            case 'ack8'
                r = r + 1; F(r, :) = X.ack8;
            case 'tsince'
                r = r + 1; F(r, :) = min(1, X.tsince / 20);
            case 'offtrend'
                r = r + 1; F(r, :) = max(-2, min(2, X.offtrend / 2));
        end
    end
end
