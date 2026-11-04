function n = nCtxBins_v13(env)
% nCtxBins_v13  Number of context-table bins.
    n = numel(env.ctx_edges) + 1;
    if strcmpi(env.ctx_cue, 'dslack'), n = 2 * n; end
end
