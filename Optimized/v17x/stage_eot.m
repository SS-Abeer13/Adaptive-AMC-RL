function stage_eot(ctx)
% stage_eot  Task 2 end-of-trace sensitivity stage and Task 3 D-PF diagnostic.
% Evaluates stored schemes under asrun and resolved modes, asserts exact
% reproduction of all stored per-trace values in asrun mode, and computes
% D-PF diagnostic for M2 and M4.
% Checkpoints keyed by SHA-256 of stage_eot.m, all .m in eot/, and unit config.

    addpath(ctx.v17);
    eot_dir = fullfile(ctx.root, 'eot');
    addpath(eot_dir);
    addpath(fullfile(ctx.root, 'g6'));
    addpath(fullfile(ctx.root, 'nr1'));
    addpath(ctx.root);
    v17_setup;

    stage_m = [mfilename('fullpath') '.m'];
    ctx.hbf(sprintf('stage_eot: starting stage eot (smoke=%d)', ctx.smoke));

    n_eval_nr2 = ternary(ctx.smoke, 2, 500);
    n_eval_m1  = ternary(ctx.smoke, 2, 500);
    n_eval_g2  = ternary(ctx.smoke, 2, 300);
    n_eval_g3  = ternary(ctx.smoke, 2, 300);
    n_eval_m2  = ternary(ctx.smoke, 2, 500);
    n_eval_m4  = ternary(ctx.smoke, 2, 500);

    % ---- Units 1 & 2: NR2 ----
    h_as_nr2 = compute_unit_hash('NR2', 'asrun', 'scheduled', {'nr2_all'}, ctx.smoke, stage_m, eot_dir);
    u_as_nr2 = unit_with_hash(ctx, 'asrun_NR2', @() eval_set_eot('NR2', 'asrun', n_eval_nr2, ctx), h_as_nr2);

    h_res_nr2 = compute_unit_hash('NR2', 'resolved', 'scheduled', {'nr2_all'}, ctx.smoke, stage_m, eot_dir);
    u_res_nr2 = unit_with_hash(ctx, 'resolved_NR2', @() eval_set_eot('NR2', 'resolved', n_eval_nr2, ctx), h_res_nr2);

    % ---- Units 3 & 4: M1 ----
    h_as_m1 = compute_unit_hash('M1', 'asrun', 'scheduled', {'m1_all'}, ctx.smoke, stage_m, eot_dir);
    u_as_m1 = unit_with_hash(ctx, 'asrun_M1', @() eval_set_eot('M1', 'asrun', n_eval_m1, ctx), h_as_m1);

    h_res_m1 = compute_unit_hash('M1', 'resolved', 'scheduled', {'m1_all'}, ctx.smoke, stage_m, eot_dir);
    u_res_m1 = unit_with_hash(ctx, 'resolved_M1', @() eval_set_eot('M1', 'resolved', n_eval_m1, ctx), h_res_m1);

    % ---- Units 5 & 6: G2 ----
    h_as_g2 = compute_unit_hash('G2', 'asrun', 'scheduled', {'g2_all'}, ctx.smoke, stage_m, eot_dir);
    u_as_g2 = unit_with_hash(ctx, 'asrun_G2', @() eval_set_eot('G2', 'asrun', n_eval_g2, ctx), h_as_g2);

    h_res_g2 = compute_unit_hash('G2', 'resolved', 'scheduled', {'g2_all'}, ctx.smoke, stage_m, eot_dir);
    u_res_g2 = unit_with_hash(ctx, 'resolved_G2', @() eval_set_eot('G2', 'resolved', n_eval_g2, ctx), h_res_g2);

    % ---- Units 7 & 8: G3 ----
    h_as_g3 = compute_unit_hash('G3', 'asrun', 'scheduled', {'g3_all'}, ctx.smoke, stage_m, eot_dir);
    u_as_g3 = unit_with_hash(ctx, 'asrun_G3', @() eval_set_eot('G3', 'asrun', n_eval_g3, ctx), h_as_g3);

    h_res_g3 = compute_unit_hash('G3', 'resolved', 'scheduled', {'g3_all'}, ctx.smoke, stage_m, eot_dir);
    u_res_g3 = unit_with_hash(ctx, 'resolved_G3', @() eval_set_eot('G3', 'resolved', n_eval_g3, ctx), h_res_g3);

    % ---- Unit 9: pfdiag_M2 ----
    h_pf_m2 = compute_unit_hash('M2', 'both', 'both', {'m2_schemes'}, ctx.smoke, stage_m, eot_dir);
    u_pf_m2 = unit_with_hash(ctx, 'pfdiag_M2', @() eval_pfdiag_eot('M2', n_eval_m2, ctx), h_pf_m2);

    % ---- Unit 10: pfdiag_M4 ----
    h_pf_m4 = compute_unit_hash('M4', 'both', 'both', {'m4_schemes'}, ctx.smoke, stage_m, eot_dir);
    u_pf_m4 = unit_with_hash(ctx, 'pfdiag_M4', @() eval_pfdiag_eot('M4', n_eval_m4, ctx), h_pf_m4);

    % ---- Unit 11: summary ----
    h_sum = compute_unit_hash('summary', 'both', 'both', {'summary'}, ctx.smoke, stage_m, eot_dir);
    unit_with_hash(ctx, 'summary', @() report_eot_summary( ...
        u_as_nr2.data, u_res_nr2.data, ...
        u_as_m1.data, u_res_m1.data, ...
        u_as_g2.data, u_res_g2.data, ...
        u_as_g3.data, u_res_g3.data, ...
        u_pf_m2.data, u_pf_m4.data, ctx), h_sum);

    ctx.hbf('stage_eot done successfully');
end

% =========================================================================
% Hash-keyed checkpoint runner
% =========================================================================
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
                ctx.hbf(sprintf('unit %s: hash mismatch (recomputing)', name));
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

function h = compute_unit_hash(set_name, eot_mode, pf_avg, scheme_list, smoke, stage_m, eot_dir)
    hasher = java.security.MessageDigest.getInstance('SHA-256');

    % 1. stage_eot.m code bytes
    fid = fopen(stage_m, 'r');
    if fid > 0
        b = fread(fid, '*uint8');
        fclose(fid);
        hasher.update(b);
    end

    % 2. Every .m in eot_dir in sorted order
    mfiles = dir(fullfile(eot_dir, '*.m'));
    if ~isempty(mfiles)
        [~, idx] = sort({mfiles.name});
        mfiles = mfiles(idx);
        for k = 1:numel(mfiles)
            fid = fopen(fullfile(eot_dir, mfiles(k).name), 'r');
            if fid > 0
                b = fread(fid, '*uint8');
                fclose(fid);
                hasher.update(b);
            end
        end
    end

    % 3. Config struct
    cfg = struct('set', set_name, 'eot_mode', eot_mode, 'pf_avg', pf_avg, ...
                 'scheme_list', {scheme_list}, 'smoke', smoke);
    cfg_str = jsonencode(cfg);
    hasher.update(uint8(cfg_str));

    bytes = hasher.digest();
    h = sprintf('%02x', typecast(bytes, 'uint8'));
end

function y = ternary(c, a, b)
    if c, y = a; else, y = b; end
end
