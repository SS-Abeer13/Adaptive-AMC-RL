function results = runCase23_v4(varargin)
% runCase23_v4  5-user AMC + scheduler (Cases 2/3) on the v4 stack.
%   results = runCase23_v4();
%   results = runCase23_v4('n_seeds', 5, 'n_eval', 30);   % camera-ready
%
% Trains on PF, evaluates on PF/RR/EQ without retraining (robustness sweep:
% the flatter degradation curve is the "A2C is most robust" evidence).

    opts = struct(varargin{:});
    results = runComparison_v4(23, opts);
end
