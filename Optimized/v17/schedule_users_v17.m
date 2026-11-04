function rb_alloc = schedule_users_v17(mode, t, N, R_emas, pot, total_RBs, dl)
% schedule_users_v17  v5 allocator plus 'edf' (earliest deadline first).
%   dl : 1 x N absolute deadline TTI of each user's head-of-line packet
%        (Inf for users without a packet). Only used by 'edf'.
%   'edf': all RBs to the user with data (pot > 0) whose deadline is
%          earliest; ties broken by the PF metric pot ./ max(R_emas, 0.1).
%          With no deadline information (dl absent or all Inf) EDF = PF.
%   Every other mode is passed to schedule_users_v5 unchanged.
    if ~strcmpi(mode, 'edf')
        rb_alloc = schedule_users_v5(mode, t, N, R_emas, pot, total_RBs);
        return;
    end
    rb_alloc = zeros(1, N);
    if nargin < 7 || isempty(dl) || all(~isfinite(dl))
        rb_alloc = schedule_users_v5('pf', t, N, R_emas, pot, total_RBs);
        return;
    end
    cand = find(pot > 0);
    if isempty(cand), return; end
    dmin = min(dl(cand));
    cand = cand(dl(cand) == dmin);
    [~, b] = max(pot(cand) ./ max(R_emas(cand), 0.1));
    rb_alloc(cand(b)) = total_RBs;
end
