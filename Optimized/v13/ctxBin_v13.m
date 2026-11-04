function b = ctxBin_v13(env, X)
% ctxBin_v13  Context-table bin per user. 'dslack' = deadline class (budget
% <= 5 / > 5 TTI) x slack bins; every other cue = bins of the cue value.
    b = cueBin_v13(env, cueVal_v13(env, X));
    if strcmpi(env.ctx_cue, 'dslack')
        dcl = 1 + double(userDeadline_v13(env, numel(b)) > 5);
        b = b + (numel(env.ctx_edges) + 1) * (dcl - 1);
    end
end
