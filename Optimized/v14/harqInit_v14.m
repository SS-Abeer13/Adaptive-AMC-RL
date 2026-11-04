function H = harqInit_v14(N)
% harqInit_v14  Initializes per-user HARQ Chase-combining tracker.
% Tracks:
%   pend : Boolean flag indicating pending retransmission
%   nret : Current retransmission attempt count (1, 2, ..., harq_max_retx)
%   tbs  : Transport block size of pending packet
%   mcs  : Original MCS of pending packet
%   sinr_eff : Running effective soft-combined SINR
    H = struct('pend', false(1, N), ...
               'nret', zeros(1, N), ...
               'tbs',  zeros(1, N), ...
               'mcs',  zeros(1, N), ...
               'sinr_eff', zeros(1, N));
end
