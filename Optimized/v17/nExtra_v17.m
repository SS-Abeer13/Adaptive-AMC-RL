function n = nExtra_v17(env)
% nExtra_v17  Number of extra state rows requested by env.feat_extra.
    n = 0;
    if ~isfield(env, 'feat_extra') || isempty(env.feat_extra), return; end
    for k = 1:numel(env.feat_extra)
        switch lower(env.feat_extra{k})
            case {'age', 'dev', 'cellnack', 'dline'}, n = n + 1;
            case 'slack', n = n + 3;
            case 'harqx', n = n + 3;  % PLAN_v17 A4: busy procs, retx-ready, in-flight bits
            case {'ack8', 'tsince', 'offtrend'}, n = n + 1;
            otherwise, error('nExtra_v17: unknown feature "%s"', env.feat_extra{k});
        end
    end
end
