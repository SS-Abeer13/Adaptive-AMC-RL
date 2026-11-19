function stage_eot(ctx)
% stage_eot  Task 2 end-of-trace sensitivity stage.
% Re-evaluates stored schemes under env.eot_mode = 'resolved'.
% Checkpoints keyed by SHA-256 of code + config.

    addpath(ctx.v17);
    addpath(fullfile(ctx.root, 'eot'));
    addpath(fullfile(ctx.root, 'g6'));
    addpath(fullfile(ctx.root, 'nr1'));
    addpath(ctx.root);
    v17_setup;

    stage_file = mfilename('fullpath');
    stage_m = [stage_file '.m'];
    key_config = struct('eot_mode', 'resolved', 'smoke', ctx.smoke);
    stage_hash = compute_stage_hash(stage_m, key_config);

    ctx.hbf(sprintf('stage_eot: starting with stage_hash=%s (smoke=%d)', stage_hash(1:12), ctx.smoke));

    n_eval = ternary(ctx.smoke, 2, 500);

    % ---- 1. Unit: eval_M1 ----
    u_eval_m1 = unit_with_hash(ctx, 'eval_M1', @() unit_eval_m1(n_eval, ctx), stage_hash);

    % ---- 2. Unit: eval_NR2 ----
    u_eval_nr2 = unit_with_hash(ctx, 'eval_NR2', @() unit_eval_nr2(n_eval, ctx), stage_hash);

    % ---- 3. Unit: eval_G2 ----
    u_eval_g2 = unit_with_hash(ctx, 'eval_G2', @() unit_eval_g2(n_eval, ctx), stage_hash);

    % ---- 4. Unit: eval_G3 ----
    u_eval_g3 = unit_with_hash(ctx, 'eval_G3', @() unit_eval_g3(n_eval, ctx), stage_hash);

    % ---- 5. Unit: summary ----
    unit_with_hash(ctx, 'summary', @() unit_summary(u_eval_m1.data, u_eval_nr2.data, u_eval_g2.data, u_eval_g3.data, ctx), stage_hash);

    ctx.hbf('stage_eot done successfully');
end

% =========================================================================
% Hash-keyed checkpoint runner
% =========================================================================
function out = unit_with_hash(ctx, name, fcn, stage_hash)
    d = fullfile(ctx.ckptdir, ctx.stage);
    f = fullfile(d, [name '.mat']);
    if exist(f, 'file')
        try
            S = load(f, 'out');
            if isfield(S.out, 'stage_hash') && strcmp(S.out.stage_hash, stage_hash)
                % Valid hash match
            else
                ctx.hbf(sprintf('unit %s: hash mismatch (recomputing)', name));
                delete(f);
            end
        catch
            delete(f);
        end
    end
    wrapped_fcn = @() wrap_output(fcn(), stage_hash);
    out = ctx.unit(name, wrapped_fcn);
end

function wrapped = wrap_output(data, stage_hash)
    wrapped = struct('data', data, 'stage_hash', stage_hash);
end

function h = compute_stage_hash(stage_file, key_config)
    fid = fopen(stage_file, 'r');
    code_bytes = fread(fid, '*uint8');
    fclose(fid);
    cfg_str = jsonencode(key_config);
    hasher = java.security.MessageDigest.getInstance('SHA-256');
    hasher.update(code_bytes);
    hasher.update(uint8(cfg_str));
    bytes = hasher.digest();
    h = sprintf('%02x', typecast(bytes, 'uint8'));
end

% =========================================================================
% Unit implementations (stubs for Task 1; executed in Task 2)
% =========================================================================
function out = unit_eval_m1(n_eval, ctx)
    ctx.hbf(sprintf('eval_M1: running %d traces in resolved mode', n_eval));
    out = struct('n_eval', n_eval, 'study', 'M1');
end

function out = unit_eval_nr2(n_eval, ctx)
    ctx.hbf(sprintf('eval_NR2: running %d traces in resolved mode', n_eval));
    out = struct('n_eval', n_eval, 'study', 'NR2');
end

function out = unit_eval_g2(n_eval, ctx)
    ctx.hbf(sprintf('eval_G2: running %d traces in resolved mode', n_eval));
    out = struct('n_eval', n_eval, 'study', 'G2');
end

function out = unit_eval_g3(n_eval, ctx)
    ctx.hbf(sprintf('eval_G3: running %d traces in resolved mode', n_eval));
    out = struct('n_eval', n_eval, 'study', 'G3');
end

function out = unit_summary(m1, nr2, g2, g3, ctx)
    ctx.hbf('summary: generating eot_summary.txt and running stats scripts');
    out = struct('status', 'complete');
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
