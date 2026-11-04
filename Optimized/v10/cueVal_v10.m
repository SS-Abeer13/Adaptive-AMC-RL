function v = cueVal_v10(env, X)
% cueVal_v10  Value of the context-table cue for every user (1 x N).
    N = numel(X.age);
    switch lower(env.ctx_cue)
        case 'none',     v = zeros(1, N);
        case 'age',      v = X.age;
        case 'dev',      v = X.dev;
        case 'cellnack', v = X.cn * ones(1, N);
        case {'slack', 'dslack'}, v = slackOf_v10(env, X.Q, X.t);
        otherwise, error('cueVal_v10: unknown cue "%s"', env.ctx_cue);
    end
end
