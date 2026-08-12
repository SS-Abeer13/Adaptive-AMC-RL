function results = runCase23_v6(varargin)
% runCase23_v6  Multi-user AMC + scheduler (Cases 2/3) on the v6 OLLA-relative stack.
%   results = runCase23_v6();                 % N=5, defaults
%   results = runCase23_v6('N',10);           % N-user study
%   results = runCase23_v6('N',10,'olla_warm_passes',3);   % converged-OLLA eval
%   results = runCase23_v6('N',10,'n_seeds',5,'n_eval',30,'ep_deep',600);  % camera-ready
    opts = struct(varargin{:});
    results = runComparison_v6(23, opts);
end
