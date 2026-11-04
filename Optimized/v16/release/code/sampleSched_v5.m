function mode = sampleSched_v5(env)
% sampleSched_v5  Draw a training scheduler from env.train_schedulers using
% env.train_sched_weights (PF-weighted by default). Falls back to uniform.
    w = env.train_sched_weights;
    if isempty(w) || numel(w) ~= numel(env.train_schedulers)
        w = ones(1, numel(env.train_schedulers));
    end
    w = w / sum(w);
    idx = find(rand <= cumsum(w), 1, 'first');
    if isempty(idx), idx = numel(env.train_schedulers); end
    mode = env.train_schedulers{idx};
end
