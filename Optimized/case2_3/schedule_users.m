function rb_alloc = schedule_users(mode, t, N, R_emas, potential_rates, total_RBs)
% Per-TTI resource-block allocator for N users.
%   mode = 'rr'  -> round robin, served user = mod(t-1, N) + 1
%        = 'pf'  -> proportional fair, max(potential_rate / EMA_rate)
%        = 'eq'  -> equal split, every user gets total_RBs/N
% Output: rb_alloc(i) = #RBs to user i this TTI. Sum <= total_RBs.

    if nargin < 6 || isempty(total_RBs), total_RBs = 110; end
    rb_alloc = zeros(1, N);

    switch lower(mode)
        case {'rr','roundrobin','round_robin'}
            served = mod(t-1, N) + 1;
            rb_alloc(served) = total_RBs;

        case {'pf','proportionalfair','proportional_fair','dynamic'}
            ratios = potential_rates ./ max(R_emas, 0.1);
            [~, served] = max(ratios);
            rb_alloc(served) = total_RBs;

        case {'eq','equal','share'}
            base = floor(total_RBs / N);
            rb_alloc(:) = base;
            rem = total_RBs - sum(rb_alloc);
            if rem > 0
                rb_alloc(1:rem) = rb_alloc(1:rem) + 1;
            end

        otherwise
            error('schedule_users: unknown mode "%s".', mode);
    end
end
