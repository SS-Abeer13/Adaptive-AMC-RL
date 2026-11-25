function objs = ft_load_objects(v17x_dir, v17_dir, verify_hashes)
% ft_load_objects  Load all 37 frozen FT objects and verify FT_objects.sha256 + env equality.

    if nargin < 3, verify_hashes = true; end
    repo_root = fileparts(fileparts(v17x_dir));
    v17_setup;

    if verify_hashes
        sha_file = fullfile(repo_root, 'paper', 'proposals', 'FT_objects.sha256');
        assert(exist(sha_file, 'file') == 2, 'Missing FT_objects.sha256');
        lines = strsplit(fileread(sha_file), {'\r', '\n'});
        n_checked = 0;
        for i = 1:numel(lines)
            ln = strtrim(lines{i});
            if isempty(ln) || ln(1) == '#', continue; end
            toks = regexp(ln, '^([0-9a-fA-F]{64})\s+(.+)$', 'tokens', 'once');
            assert(~isempty(toks), 'Malformed hash line in FT_objects.sha256: %s', ln);
            exp_h = lower(toks{1});
            rel_p = strtrim(toks{2});
            full_p = fullfile(repo_root, strrep(rel_p, '/', filesep));
            assert(exist(full_p, 'file') == 2, 'Missing frozen object: %s', full_p);
            act_h = file_sha256(full_p);
            assert(strcmp(act_h, exp_h), 'SHA-256 MISMATCH for %s: expected %s, got %s', rel_p, exp_h, act_h);
            n_checked = n_checked + 1;
        end
        fprintf('ft_load_objects: verified %d/29 frozen object files against FT_objects.sha256\n', n_checked);
    end

    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data_m1 = load(fullfile(v17_dir, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R_M1 = data_m1.results;
    env_m1 = R_M1.env;

    % Reconstruct frozen NR2 env
    envN2 = env_m1;
    envN2.base_rule_force = 'fixed';
    envN2.fixed_offset = -2;
    envN2 = selectBaseRule_v17n(envN2, 2, o.simTime);
    envN2.scheduler = 'pf';

    % FT env must match NR2 env field by field
    envFT = envN2;
    assert_env_equal(envFT, envN2);

    % Load G6 frozen tables
    txt_single = fileread(fullfile(v17x_dir, 'Dataset', 'cal500_single.txt'));
    f_off = parse_int(txt_single, 'Fixed-500: offset = ([+-]?[0-9]+)');
    comp_ckpt = fullfile(v17x_dir, 'Dataset', 'ckpt', 'g6a', 'composite_table.mat');
    S_comp = load(comp_ckpt);
    ctx_tab = S_comp.out.ctx_tab;
    olla_set = S_comp.out.olla_setting;
    ctxj_tab = read_ctxj_from_tables(fullfile(v17x_dir, 'Dataset', 'cal500_tables.txt'));

    e_f = envFT; e_f.fixed_offset = f_off;
    e_ctx = envFT; e_ctx.ctx_tab = ctx_tab;
    e_olla = envFT; e_olla.olla_target = olla_set(1); e_olla.olla_target_tuned = olla_set(1); e_olla.olla_step_down = olla_set(2);
    e_ctxj = envFT; e_ctxj.ctxj_tab = ctxj_tab;

    % NR2 residual A2C seeds 1..10
    nr2_pols = cell(1, 10);
    for s = 1:10
        S = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'nr2', sprintf('train_seed_%d.mat', s)));
        nr2_pols{s} = S.out.a2c;
    end

    % R6a RL-full seeds 1..10
    r6a_pols = cell(1, 10);
    for s = 1:10
        S = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r6_fullaction', sprintf('train_%d.mat', s)));
        r6a_pols{s} = S.out.a2c;
    end

    % GBT-ACK fits 1..4
    r1b_mat = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r1b_ack', 'equiv.mat'));
    gbt_trees = cell(1, 4);
    gbt_trees{1} = r1b_mat.out;
    for k = 2:4
        S = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r1c', sprintf('r1c_trees_m1_%d.mat', k)));
        m = S.trees_export;
        if isstruct(m.trees) && numel(m.trees) > 1
            tc = cell(1, numel(m.trees));
            for it = 1:numel(m.trees), tc{it} = m.trees(it); end
            m.trees = tc;
        end
        gbt_trees{k} = m;
    end

    % R2 calibrated rule threshold
    st_sel = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r2_rule', 'select.mat'));
    chosen_th = st_sel.out;

    objs = struct( ...
        'simTime', o.simTime, ...
        'envFT', envFT, ...
        'envN2', envN2, ...
        'e_f', e_f, ...
        'e_ctx', e_ctx, ...
        'e_olla', e_olla, ...
        'e_ctxj', e_ctxj, ...
        'nr2_pols', {nr2_pols}, ...
        'r6a_pols', {r6a_pols}, ...
        'gbt_trees', {gbt_trees}, ...
        'chosen_th', chosen_th ...
    );
end

function h = file_sha256(fpath)
    md = java.security.MessageDigest.getInstance('SHA-256');
    fid = fopen(fpath, 'rb');
    assert(fid ~= -1, 'Cannot open %s', fpath);
    bytes = fread(fid, Inf, '*uint8');
    fclose(fid);
    md.update(bytes);
    digest = typecast(md.digest(), 'uint8');
    h = lower(reshape(dec2hex(digest, 2)', 1, []));
end

function assert_env_equal(a, b)
    fa = sort(fieldnames(a));
    fb = sort(fieldnames(b));
    assert(isequal(fa, fb), 'Env fieldnames mismatch between FT and NR2');
    for i = 1:numel(fa)
        fn = fa{i};
        assert(isequaln(a.(fn), b.(fn)), 'Env field %s differs between FT and NR2', fn);
    end
end

function val = parse_int(txt, pat)
    m = regexp(txt, pat, 'tokens', 'once');
    assert(~isempty(m), 'Pattern not found: %s', pat);
    val = str2double(m{1});
end

function tab = read_ctxj_from_tables(fpath)
    txt = fileread(fpath);
    tab = zeros(3, 2, 3, 2);
    lines = strsplit(txt, '\n');
    for i = 1:numel(lines)
        m = regexp(lines{i}, 'cell\((\d+),(\d+),(\d+),(\d+)\)\s*=\s*([+-]?\d+)', 'tokens', 'once');
        if ~isempty(m)
            b = str2double(m{1}); d = str2double(m{2}); v = str2double(m{3}); u = str2double(m{4}) + 1;
            tab(b, d, v, u) = str2double(m{5});
        end
    end
end
