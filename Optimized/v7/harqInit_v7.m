function H = harqInit_v7(N)
% harqInit_v7  Fresh per-user HARQ state.
    H = struct('pend', false(1, N), 'nret', zeros(1, N), ...
               'tbs', zeros(1, N),  'mcs',  zeros(1, N));
end
