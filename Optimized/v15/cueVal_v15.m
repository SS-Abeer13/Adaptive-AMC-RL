function v = cueVal_v15(env, X)
% cueVal_v15  Value of the context-table cue for every user (1 x N).
    N = numel(X.age);
    switch lower(env.ctx_cue)
        case 'none',     v = zeros(1, N);
        case 'age',      v = X.age;
        case 'dev',      v = X.dev;
        case 'cellnack', v = X.cn * ones(1, N);
        case {'slack', 'dslack'}, v = slackOf_v15(env, X.Q, X.t);
        case 'ack8',     v = X.ack8;
        case 'tsince',   v = X.tsince;
        case 'offtrend', v = X.offtrend;
        otherwise, error('cueVal_v15: unknown cue "%s"', env.ctx_cue);
    end
end
