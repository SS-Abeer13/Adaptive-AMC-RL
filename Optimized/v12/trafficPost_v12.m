function [Q, ok] = trafficPost_v12(Q, tp, t)
% trafficPost_v12  After transmission: subtract delivered bits (tp in Mbps =
% kbit per 1 ms TTI) and complete packets.
    N = numel(Q.has); ok = false(1, N);
    if ~Q.on, return; end
    for i = 1:N
        if Q.has(i) && tp(i) > 0
            Q.rem(i) = Q.rem(i) - tp(i) * 1e3;
            if Q.rem(i) <= 0
                ok(i) = true; Q.has(i) = false;
                if Q.arr(i) > Q.countFrom
                    Q.okU(i) = Q.okU(i) + 1; Q.resU(i) = Q.resU(i) + 1;
                end
            end
        end
    end
end
