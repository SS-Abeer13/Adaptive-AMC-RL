function b = cueBin_v13(env, v)
% cueBin_v13  Bin index (1..numel(edges)+1) of cue values v (1 x N).
    e = env.ctx_edges(:).';
    b = ones(size(v));
    for k = 1:numel(e), b = b + double(v > e(k)); end
end
