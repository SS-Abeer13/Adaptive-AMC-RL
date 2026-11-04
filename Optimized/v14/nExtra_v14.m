function n = nExtra_v14(env)
% nExtra_v14  Number of extra state rows requested by env.feat_extra.
    n = 0;
    if ~isfield(env, 'feat_extra') || isempty(env.feat_extra), return; end
    for k = 1:numel(env.feat_extra)
        switch lower(env.feat_extra{k})
            case {'age', 'dev', 'cellnack', 'dline'}, n = n + 1;
            case 'slack', n = n + 3;
            % P4 (IMPLEMENTATION_PLAN_v14.md, README_v14.md): 'ack8' = EMA
            % proxy for the fraction of ACKs over the last ~8 scheduled
            % attempts (not an exact 8-slot window -- see featExtra_v14);
            % 'tsince' = TTIs since last scheduled; 'offtrend' = OLLA
            % offset minus its own slow EMA (short-term trend proxy).
            case {'ack8', 'tsince', 'offtrend'}, n = n + 1;
            otherwise, error('nExtra_v14: unknown feature "%s"', env.feat_extra{k});
        end
    end
end
