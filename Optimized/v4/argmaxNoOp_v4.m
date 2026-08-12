function a = argmaxNoOp_v4(q, no_op_idx)
% argmaxNoOp_v4  Greedy action with ties broken toward the no-op (v4.1).
%   Plain max() breaks ties by index order, i.e. action -2: in any
%   unvisited/flat state the greedy policy then slams CQI downward (this is
%   what collapsed Q-Learning in the first v4 run). Preferring the neutral
%   "keep current CQI" action on ties is the principled default.
    q = q(:);
    m = max(q);
    ties = find(q >= m - 1e-12);
    if any(ties == no_op_idx)
        a = no_op_idx;
    else
        a = ties(1);
    end
end
