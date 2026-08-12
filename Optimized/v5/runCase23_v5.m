function results = runCase23_v5(varargin)
% runCase23_v5  Multi-user AMC + scheduler (Cases 2/3) on the merged v5 stack.
%   results = runCase23_v5();                 % N=5, defaults
%   results = runCase23_v5('N',50);           % shared-parameter scale study
%   results = runCase23_v5('N',50,'n_seeds',5,'n_eval',30);  % camera-ready
    opts = struct(varargin{:});
    results = runComparison_v5(23, opts);
end
