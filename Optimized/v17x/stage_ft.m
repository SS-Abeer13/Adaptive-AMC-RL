function stage_ft(ctx)
% stage_ft  Amendment 13 / 14 fresh-trace confirmation stage (FT).
% Checkpoints keyed by SHA-256 of stage_ft.m, all .m in ft/, and unit config.

    addpath(ctx.v17);
    ft_dir = fullfile(ctx.root, 'ft');
    addpath(ft_dir);
    addpath(fullfile(ctx.root, 'eot'));
    addpath(fullfile(ctx.root, 'g6'));
    addpath(fullfile(ctx.root, 'nr1'));
    addpath(ctx.root);
    v17_setup;

    stage_m = [mfilename('fullpath') '.m'];
    ctx.hbf(sprintf('stage_ft: starting stage ft (smoke=%d)', ctx.smoke));

    % 1. Widened disjointness check (Amendment 14 Section 4)
    py_exe = 'python';
    disj_py = fullfile(ft_dir, 'check_disjointness_ft.py');
    [rc, out_txt] = system(sprintf('"%s" "%s"', py_exe, disj_py));
    assert(rc == 0, 'FT disjointness check failed:\n%s', out_txt);
    ctx.hbf('stage_ft: widened disjointness check PASSED (0 collisions)');

    n_repro = ternary(ctx.smoke, 2, 20);
    n_eval  = ternary(ctx.smoke, 2, 500);

    % 2. REPRO gate (hard stop)
    h_repro = compute_unit_hash('repro', n_repro, ctx.smoke, stage_m, ft_dir);
    unit_with_hash(ctx, 'ft_repro', @() eval_ft_pass('repro', n_repro, ctx), h_repro);

    % 3. FT as-run pass (primary)
    h_asrun = compute_unit_hash('asrun', n_eval, ctx.smoke, stage_m, ft_dir);
    unit_with_hash(ctx, 'ft_asrun', @() eval_ft_pass('asrun', n_eval, ctx), h_asrun);

    % 4. FT resolved pass (secondary, gated on EOT bit-identity which passed 0.0 diff)
    h_res = compute_unit_hash('resolved', n_eval, ctx.smoke, stage_m, ft_dir);
    unit_with_hash(ctx, 'ft_resolved', @() eval_ft_pass('resolved', n_eval, ctx), h_res);

    % 5. Run ft_stats.py unchanged on asrun and resolved
    h_stat = compute_unit_hash('stats', n_eval, ctx.smoke, stage_m, ft_dir);
    unit_with_hash(ctx, 'ft_stats', @() run_ft_stats(ctx, py_exe), h_stat);

    ctx.hbf('stage_ft done successfully');
end

function out = run_ft_stats(ctx, py_exe)
    repo_root = fileparts(fileparts(ctx.root));
    stats_py = fullfile(repo_root, 'paper', 'analysis', 'ft_stats.py');
    ft_ds = fullfile(ctx.root, 'Dataset', 'ft');
    asrun_csv = fullfile(ft_ds, 'pertrace_ft_asrun.csv');
    res_csv   = fullfile(ft_ds, 'pertrace_ft_resolved.csv');
    out_res   = fullfile(ft_ds, 'out_resolved');
    if ~exist(out_res, 'dir'), mkdir(out_res); end

    cmd1 = sprintf('"%s" "%s" --in "%s" --out "%s"', py_exe, stats_py, asrun_csv, ft_ds);
    [rc1, txt1] = system(cmd1);
    assert(rc1 == 0, 'ft_stats.py failed on asrun:\n%s', txt1);

    cmd2 = sprintf('"%s" "%s" --in "%s" --out "%s"', py_exe, stats_py, res_csv, out_res);
    [rc2, txt2] = system(cmd2);
    assert(rc2 == 0, 'ft_stats.py failed on resolved:\n%s', txt2);

    ctx.hbf('run_ft_stats: ft_stats.py completed on asrun and resolved');
    out = struct('ok', 1);
end

function out = unit_with_hash(ctx, name, fcn, unit_hash)
    d = fullfile(ctx.ckptdir, ctx.stage);
    if ~exist(d, 'dir'), mkdir(d); end
    f = fullfile(d, [name '.mat']);
    if exist(f, 'file')
        try
            S = load(f, 'out');
            if isfield(S.out, 'unit_hash') && strcmp(S.out.unit_hash, unit_hash)
                ctx.hbf(sprintf('unit %s: checkpoint valid (skipping recompute)', name));
                out = S.out;
                return;
            else
                delete(f);
            end
        catch
            delete(f);
        end
    end
    wrapped_fcn = @() wrap_output(fcn(), unit_hash);
    out = ctx.unit(name, wrapped_fcn);
end

function wrapped = wrap_output(data, unit_hash)
    wrapped = struct('data', data, 'unit_hash', unit_hash);
end

function h = compute_unit_hash(mode, n_eval, smoke, stage_m, ft_dir)
    hasher = java.security.MessageDigest.getInstance('SHA-256');
    hasher.update(uint8(fileread(stage_m)));
    mfiles = dir(fullfile(ft_dir, '*.m'));
    [~, ord] = sort({mfiles.name});
    for i = 1:numel(ord)
        fp = fullfile(ft_dir, mfiles(ord(i)).name);
        hasher.update(uint8(mfiles(ord(i)).name));
        hasher.update(uint8(fileread(fp)));
    end
    cfg_str = sprintf('%s|%d|%d', mode, n_eval, smoke);
    hasher.update(uint8(cfg_str));
    bytes = typecast(hasher.digest(), 'uint8');
    h = lower(reshape(dec2hex(bytes, 2)', 1, []));
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
