function a = argmaxNoOp_v5(q, no_op_idx)
% argmaxNoOp_v5  Greedy action, ties broken toward the no-op (offset 0).
%   Plain max() breaks ties to the first index (offset -2), which collapsed
%   Q-Learning in the first v4 run. On a tie, offset 0 == "use the baseline
%   CQI", the principled neutral default for unvisited states.
    q = q(:); m = max(q); ties = find(q >= m - 1e-12);
    if any(ties == no_op_idx), a = no_op_idx; else, a = ties(1); end
end
