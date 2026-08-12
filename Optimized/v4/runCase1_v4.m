function results = runCase1_v4(varargin)
% runCase1_v4  Single-user AMC (Case 1) on the v4 stack.
%   results = runCase1_v4();
%   results = runCase1_v4('n_seeds', 5, 'n_eval', 30);
%
% Fixes vs optimized/case1: the agent's MCS now determines BOTH the TBS and
% the BLER (audit C1; rate is no longer taken from the baseline mapping),
% observations are delayed/noisy CQI (C2), and the comparison is multi-seed
% with held-out traces and CIs.

    opts = struct(varargin{:});
    results = runComparison_v4(1, opts);
end
