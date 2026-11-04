function stage_g1(ctx)
% stage_g1  G1 re-cut of residual-action shares (spec: paper/analysis/G1_SPEC.md).
% Wraps Optimized/v17/g1/g1_recut_v17.m for the cases M1 and M3. The stage is
% treated as done only if the summary file shows, for BOTH cases, a bit-identical
% instrumented evaluator and a reproduction difference of exactly 0.
    if g1_complete(ctx)
        ctx.hbf('G1 outputs already complete and valid: skipped');
        return
    end
    ctx.hbf('running g1_recut_v17 for M1_dl_rtt8 and M3_gp_rtt8 (20-60 min)');
    G1_CASES = {'M1_dl_rtt8', 'M3_gp_rtt8'}; %#ok<NASGU>   % read by the script
    addpath(fullfile(ctx.v17, 'g1'));
    g1_recut_v17;                                          % script runs in this workspace
    if ~g1_complete(ctx)
        error('v17x:g1', 'G1 finished but EQUIV/REPRO checks in g1_summary.txt are not clean');
    end
    ctx.hbf('G1 done; EQUIV and REPRO clean');
end

function ok = g1_complete(ctx)
    ok = false;
    sf = fullfile(ctx.v17, 'paper', 'g1', 'g1_summary.txt');
    cf = fullfile(ctx.v17, 'paper', 'g1', 'g1_action_by_state.csv');
    if ~exist(sf, 'file') || ~exist(cf, 'file'), return; end
    txt = fileread(sf);
    for tag = {'M1_dl_rtt8', 'M3_gp_rtt8'}
        t = tag{1};
        e = regexp(txt, ['EQUIV\|' t '\|instrumented_vs_frozen_bit_identical=1'], 'once');
        r = regexp(txt, ['REPRO\|' t '\|max_abs_diff_cell_goodput_vs_stored=([0-9.eE+-]+)'], 'tokens', 'once');
        if isempty(e) || isempty(r) || str2double(r{1}) ~= 0, return; end
    end
    ok = true;
end
