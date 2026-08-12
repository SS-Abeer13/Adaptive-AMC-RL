function b = trendBin_v5(dS, edges)
% trendBin_v5  3-bin observed-SINR-trend discretization.
%   1 = falling (dS<edges(1)) | 2 = flat | 3 = rising (dS>edges(2)).
    if dS < edges(1), b = 1; elseif dS > edges(2), b = 3; else, b = 2; end
end
