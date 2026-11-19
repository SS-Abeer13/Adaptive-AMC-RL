function [Q, ok] = trafficPost_eot(Q, tp, t)
% trafficPost_eot  After transmission: subtract delivered bits and complete packets.
% Bit-identical to trafficPost_v17 under env.eot_mode = 'asrun'.
    N = numel(Q.has); ok = false(1, N);
    if ~Q.on, return; end
    countTo = Inf;
    if isfield(Q, 'countTo'), countTo = Q.countTo; end
    for i = 1:N
        if Q.has(i) && tp(i) > 0
            Q.rem(i) = Q.rem(i) - tp(i) * 1e3;
            if Q.rem(i) <= 0
                ok(i) = true; Q.has(i) = false;
                if Q.arr(i) > Q.countFrom && Q.dl(i) <= countTo
                    Q.okU(i) = Q.okU(i) + 1; Q.resU(i) = Q.resU(i) + 1;
                end
            end
        end
    end
end
