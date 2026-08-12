function rb_alloc = schedule_users_v4(mode, t, N, R_emas, potential_rates, total_RBs)
% schedule_users_v4  Per-interval RB allocator.
%   'rr'  round robin (whole band to one user)
%   'pf'  proportional fair on potential_rate / EMA_rate (whole band)
%   'eq'  equal split
%   'all' single-user: whole band to user 1 (Case 1)

    rb_alloc = zeros(1, N);
    switch lower(mode)
        case 'all'
            rb_alloc(1) = total_RBs;
        case {'rr', 'roundrobin'}
            rb_alloc(mod(t-1, N) + 1) = total_RBs;
        case {'pf', 'proportionalfair', 'dynamic'}
            ratios = potential_rates ./ max(R_emas, 0.1);
            [~, served] = max(ratios);
            rb_alloc(served) = total_RBs;
        case {'eq', 'equal', 'share'}
            base = floor(total_RBs / N);
            rb_alloc(:) = base;
            rem = total_RBs - sum(rb_alloc);
            if rem > 0, rb_alloc(1:rem) = rb_alloc(1:rem) + 1; end
        otherwise
            error('schedule_users_v4: unknown mode "%s"', mode);
    end
end
