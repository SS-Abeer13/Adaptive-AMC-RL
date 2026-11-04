function b = cueBin_v11(env, v)
% cueBin_v11  Bin index (1..numel(edges)+1) of cue values v (1 x N).
    e = env.ctx_edges(:).';
    b = ones(size(v));
    for k = 1:numel(e), b = b + double(v > e(k)); end
end
