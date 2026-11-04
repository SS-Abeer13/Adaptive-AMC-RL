function analyze_v16_rtteff(fid, prefix)
% analyze_v16_rtteff  Analyze RTT and deadline effects across Z1, Z2, Z3.
% Emits RTTEFF| lines comparing RTT impact (Z1 vs Z2), deadline impact (Z1 vs Z3),
% and gain vs Fixed.
    if nargin < 1 || isempty(fid), fid = 1; end
    if nargin < 2 || isempty(prefix), prefix = ''; end

    here = fileparts(mfilename('fullpath'));
    ds = fullfile(here, 'Dataset');
    f1 = fullfile(ds, sprintf('results_v16_%sZ1_rtt8.mat', prefix));
    f2 = fullfile(ds, sprintf('results_v16_%sZ2_rtt4.mat', prefix));
    f3 = fullfile(ds, sprintf('results_v16_%sZ3_rtt8_loose.mat', prefix));

    if ~exist(f1, 'file') || ~exist(f2, 'file') || ~exist(f3, 'file')
        return;
    end

    L1 = load(f1, 'results'); r1 = L1.results;
    L2 = load(f2, 'results'); r2 = L2.results;
    L3 = load(f3, 'results'); r3 = L3.results;

    [a2c1, fix1, pu1] = getScores(r1);
    [a2c2, fix2, pu2] = getScores(r2);
    [a2c3, fix3, pu3] = getScores(r3);

    fprintf(fid, '\n### RTT AND DEADLINE EFFECT ANALYSIS (RTTEFF)\n');
    fprintf(fid, 'RTTEFF|Z1_rtt8|rtt=8|dl=10|a2c=%.4f|fixed=%.4f|gain=%.4f|gain_pct=%.2f%%\n', ...
            a2c1, fix1, a2c1 - fix1, 100*(a2c1 - fix1)/max(fix1, 1e-6));
    fprintf(fid, 'RTTEFF|Z2_rtt4|rtt=4|dl=10|a2c=%.4f|fixed=%.4f|gain=%.4f|gain_pct=%.2f%%\n', ...
            a2c2, fix2, a2c2 - fix2, 100*(a2c2 - fix2)/max(fix2, 1e-6));
    fprintf(fid, 'RTTEFF|Z3_rtt8_loose|rtt=8|dl=20|a2c=%.4f|fixed=%.4f|gain=%.4f|gain_pct=%.2f%%\n', ...
            a2c3, fix3, a2c3 - fix3, 100*(a2c3 - fix3)/max(fix3, 1e-6));

    % RTT effect: Z2 (RTT=4) -> Z1 (RTT=8) at DL=10
    d_fix_rtt = fix1 - fix2;
    d_a2c_rtt = a2c1 - a2c2;
    fprintf(fid, 'RTTEFF|DELTA_RTT_EFFECT|fixed_drop=%.4f|a2c_drop=%.4f|rtt_resilience=%.4f\n', ...
            d_fix_rtt, d_a2c_rtt, (a2c1 - fix1) - (a2c2 - fix2));

    % Deadline effect: Z1 (DL=10) -> Z3 (DL=20) at RTT=8
    d_fix_dl = fix3 - fix1;
    d_a2c_dl = a2c3 - a2c1;
    fprintf(fid, 'RTTEFF|DELTA_DL_EFFECT|fixed_gain=%.4f|a2c_gain=%.4f|loose_dl_slack=%.4f\n', ...
            d_fix_dl, d_a2c_dl, (a2c3 - fix3) - (a2c1 - fix1));
end

function [a2cScore, fixScore, puScore] = getScores(r)
    M = r.metrics(1);
    a2cInd = find(strcmpi(r.schemes, 'Deep A2C v16'), 1);
    if isempty(a2cInd), a2cInd = find(contains(r.schemes, 'Deep A2C'), 1); end
    fixInd = find(strcmpi(r.schemes, 'Fixed'), 1);
    puInd = find(strcmpi(r.schemes, 'FixedPU (Oracle)'), 1);

    a2cScore = mean(mean(M.primary{a2cInd}, 1, 'omitnan'));
    fixScore = mean(M.primary{fixInd}(1, :));
    if isempty(puInd)
        puScore = fixScore;
    else
        puScore = mean(M.primary{puInd}(1, :));
    end
end
