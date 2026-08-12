function b = trendBin_v4(dS, edges)
% trendBin_v4  3-bin discretization of the observed SINR trend (v4.1).
%   bin 1: falling (dS < edges(1)) | bin 2: flat | bin 3: rising (dS > edges(2))
    if dS < edges(1)
        b = 1;
    elseif dS > edges(2)
        b = 3;
    else
        b = 2;
    end
end
