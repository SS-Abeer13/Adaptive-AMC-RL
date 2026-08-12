function results = runCase1_v5(varargin)
% runCase1_v5  Single-user AMC (Case 1) on the merged v5 stack.
%   results = runCase1_v5();
%   results = runCase1_v5('n_seeds',5,'n_eval',30);
    opts = struct(varargin{:});
    results = runComparison_v5(1, opts);
end
