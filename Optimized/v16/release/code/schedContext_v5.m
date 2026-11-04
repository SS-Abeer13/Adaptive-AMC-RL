function [code, onehot] = schedContext_v5(mode, env)
% schedContext_v5  Map a scheduler mode to an observable state context.
%   code   : integer index into env.sched_list (1..nSched)
%   onehot : nSched x 1 one-hot vector
%
% Making the scheduler regime observable lets ONE policy specialize per
% regime instead of averaging across pf/rr/eq (the v5.1 trade-off that cost
% PF performance). All learners receive the same context so the comparison
% stays information-equal: tabular agents get an extra table dimension,
% the deep agent gets a one-hot appended to its input.

    nS = numel(env.sched_list);
    code = find(strcmpi(env.sched_list, mode), 1);
    if isempty(code), code = 1; end          % unknown -> first regime
    onehot = zeros(nS, 1);
    onehot(code) = 1;
end
