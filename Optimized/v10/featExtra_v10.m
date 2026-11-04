function F = featExtra_v10(env, X)
% featExtra_v10  Extra observable state rows (nExtra x N), all gNB-side:
%   X.age (1xN TTIs since last report), X.dev (1xN dB), X.cn (scalar),
%   X.Q (traffic state), X.t (TTI).
    N = numel(X.age);
    F = zeros(nExtra_v10(env), N, 'single');
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
            case 'dline'   % v10e: the user's own latency budget (known to the gNB from its QoS class)
                r = r + 1; F(r, :) = userDeadline_v10(env, N) / max(env.pkt_deadline);
            case 'slack'
                [sl, has, rf] = slackOf_v10(env, X.Q, X.t);
                Dm = max(env.pkt_deadline);
                F(r+1, :) = min(sl, Dm) / Dm;
                F(r+2, :) = has;
                F(r+3, :) = rf;
                r = r + 3;
        end
    end
end
