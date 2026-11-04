function F = featExtra_v13(env, X)
% featExtra_v13  Extra observable state rows (nExtra x N), all gNB-side:
%   X.age (1xN TTIs since last report), X.dev (1xN dB), X.cn (scalar),
%   X.Q (traffic state), X.t (TTI). P4: X.ack8 (1xN EMA ACK fraction),
%   X.tsince (1xN TTIs since last scheduled), X.offtrend (1xN OLLA offset
%   minus its own slow EMA) -- all optional, only read when requested.
    N = numel(X.age);
    F = zeros(nExtra_v13(env), N, 'single');
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
            case 'dline'   % v13e: the user's own latency budget (known to the gNB from its QoS class)
                r = r + 1; F(r, :) = userDeadline_v13(env, N) / max(env.pkt_deadline);
            case 'slack'
                [sl, has, rf] = slackOf_v13(env, X.Q, X.t);
                Dm = max(env.pkt_deadline);
                F(r+1, :) = min(sl, Dm) / Dm;
                F(r+2, :) = has;
                F(r+3, :) = rf;
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
