% v11b_check  Short sanity run of the opportunity-cost reward (E1 environment).
v11_setup;
lf = fullfile(v11, 'logs', 'v11b_check.txt'); diary off; if exist(lf, 'file'), delete(lf); end; diary(lf);
o = base; o.reward_kind = 'oppcost';
env = defaultEnv_v11(23, 10);
fo = fieldnames(o); for q = 1:numel(fo), if isfield(env, fo{q}), env.(fo{q}) = o.(fo{q}); end, end
env.max_delta = max(abs(env.actions)); env.min_delta = -env.max_delta; env.scheduler = 'pf';
for rk = {'goodput', 'oppcost'}
    env.reward_kind = rk{1};
    [net, ~, lc, ec] = DeepA2C_Shared_v11(200, 400, 243, env);
    tpa = 0; tpo = 0; H = zeros(1, numel(env.actions));
    for j = 1:10
        rng(9000 + j); [S, ~, m] = generateChannel_v11(200, env); Ob = cqiFeedback_v11(S, env, m.delays); m.trace_id = j;
        rng(50000 + j); U = rand(200, env.N);
        [tp, ~, ~, act] = evalPolicy_v11('a2c_v11', net, S, Ob, env, m, U); tpa = tpa + sum(mean(tp(51:end, :)));
        H = H + histcounts(act(:), 0.5:1:numel(env.actions) + 0.5);
        tp = evalPolicy_v11('olla', [], S, Ob, env, m, U); tpo = tpo + sum(mean(tp(51:end, :)));
    end
    fprintf('CHECK|%s|train_tp first50=%.3f last50=%.3f|entropy last=%.3f|eval A2C=%.3f OLLA=%.3f|actions%% %s\n', rk{1}, ...
        mean(lc(1:50)), mean(lc(end-49:end)), ec(end), tpa/10, tpo/10, mat2str(round(100*H/sum(H), 1)));
end
diary off;
