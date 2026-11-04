function rb_alloc = schedule_users_v5(mode, t, N, R_emas, potential_rates, total_RBs)
% schedule_users_v5  RB allocator: 'all' (single user) | 'rr' | 'pf' | 'eq'.
    rb_alloc = zeros(1, N);
    switch lower(mode)
        case 'all'
            rb_alloc(1) = total_RBs;
        case {'rr', 'roundrobin'}
            rb_alloc(mod(t-1, N) + 1) = total_RBs;
        case {'pf', 'proportionalfair', 'dynamic'}
            [~, served] = max(potential_rates ./ max(R_emas, 0.1));
            rb_alloc(served) = total_RBs;
        case {'eq', 'equal', 'share'}
            base = floor(total_RBs / N); rb_alloc(:) = base;
            rem = total_RBs - sum(rb_alloc);
            if rem > 0, rb_alloc(1:rem) = rb_alloc(1:rem) + 1; end
        otherwise
            error('schedule_users_v5: unknown mode "%s"', mode);
    end
end
