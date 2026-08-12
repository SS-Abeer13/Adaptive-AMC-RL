function runDelay02_and_bootstrap(force_rerun)
% runDelay02_and_bootstrap  Restores delay 0/2 trace data and recalculates bootstrap CIs + Cohen's dz.
%
%   runDelay02_and_bootstrap()            % Runs delays 0/2 if missing, then computes stats
%   runDelay02_and_bootstrap(true)        % Forces re-running delays 0/2

    if nargin < 1, force_rerun = false; end
    here = fileparts(mfilename('fullpath'));
    
    delays = [0, 2, 4, 6, 8];
    nD = numel(delays);
    
    % 1. Restore Delay 0 and 2 if missing or forced
    for d = [0, 2]
        fname_mat = sprintf('FINAL_results_v6_N10_d%d_sweeppoint.mat', d);
        fname_txt = sprintf('FINAL_results_v6_N10_d%d_sweeppoint.txt', d);
        
        mat_file = fullfile(here, fname_mat);
        if ~exist(mat_file, 'file') && exist(fullfile(here, 'Dataset'), 'dir')
            mat_file = fullfile(here, 'Dataset', fname_mat);
        end
        txt_file = strrep(mat_file, '.mat', '.txt');
        
        if force_rerun || ~exist(mat_file, 'file')
            fprintf('\nRunning full-budget simulation for delay %d (5 seeds, 30 traces)...\n', d);
            res = runCase23_v6('N', 10, 'cqi_delay', d, 'n_seeds', 5, 'n_eval', 30);
            
            % Save to target files (default to Dataset if exists)
            if exist(fullfile(here, 'Dataset'), 'dir')
                mat_file = fullfile(here, 'Dataset', fname_mat);
            else
                mat_file = fullfile(here, fname_mat);
            end
            txt_file = strrep(mat_file, '.mat', '.txt');
            
            results = res;
            save(mat_file, 'results', '-v7.3');
            default_txt = fullfile(here, 'results_v6_case23_N10.txt');
            if exist(default_txt, 'file')
                copyfile(default_txt, txt_file, 'f');
            end
            fprintf('Saved delay %d results to %s\n', d, mat_file);
        else
            fprintf('Delay %d results already exist at %s. Skipping run.\n', mat_file);
        end
    end
    
    % 2. Load all delay results files
    results_cell = cell(1, nD);
    files = {
        'FINAL_results_v6_N10_d0_sweeppoint.mat', ...
        'FINAL_results_v6_N10_d2_sweeppoint.mat', ...
        'FINAL_results_v6_N10_d4_cameraready.mat', ...
        'FINAL_results_v6_N10_d6_cameraready.mat', ...
        'FINAL_results_v6_N10_d8_sweeppoint.mat'
    };
    
    for di = 1:nD
        fpath = fullfile(here, files{di});
        if ~exist(fpath, 'file')
            fpath = fullfile(here, 'Dataset', files{di});
        end
        
        if exist(fpath, 'file')
            ld = load(fpath, 'results');
            results_cell{di} = ld.results;
        else
            error('Missing required results file: %s. Please run it first.', files{di});
        end
    end
    
    % 3. Calculate bootstrap CIs and effect sizes (paired, PF scheduler)
    B = 10000;
    sched_idx = 1; % PF scheduler
    schemes = {'OLLA', 'Baseline'};
    scheme_ids = [2, 1]; % OLLA = 2, Baseline = 1
    
    output_txt = sprintf('A2C effect sizes + paired bootstrap 95%% CIs (10,000 resamples over 30 traces)\n');
    output_txt = [output_txt sprintf('N=10.  All delays: 0, 2, 4, 6, 8. Recalculated at %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'))];
    output_txt = [output_txt sprintf('============================================================================================\n')];
    output_txt = [output_txt sprintf('    cond |   vs |   A2C   ref |  margin%% [       95%% CI] |     dz win%%   r_rb\n')];
    output_txt = [output_txt sprintf('--------------------------------------------------------------------------------------------\n')];
    
    fprintf('\nCalculating bootstrap statistics (B = %d resamples)...\n', B);
    
    for di = 1:nD
        d = delays(di);
        res = results_cell{di};
        M = res.metrics(sched_idx);
        
        a2c_val = mean(M.cell_tp{5}, 1); % Mean across seeds for A2C (1 x 30 traces)
        M_traces = numel(a2c_val);
        
        for k_idx = 1:2
            ref_val = M.cell_tp{scheme_ids(k_idx)}(1, :); % Reference trace values (1 x 30 traces)
            
            % Cohen's dz
            diffs = a2c_val - ref_val;
            dz = mean(diffs) / (std(diffs) + eps);
            
            % Win rate
            win_rate = 100 * sum(a2c_val > ref_val) / M_traces;
            
            % Spearman correlation r_rb (native implementation)
            r_rb = spearman_rank_corr(a2c_val, ref_val);
            
            % Bootstrapping margin% CIs
            rng(42); % seed for reproducibility
            margins = zeros(B, 1);
            for b = 1:B
                idx = randi(M_traces, 1, M_traces);
                margins(b) = 100 * (mean(a2c_val(idx)) - mean(ref_val(idx))) / mean(ref_val(idx));
            end
            ci = prctile(margins, [2.5, 97.5]);
            
            % Line formatting
            cond_str = sprintf('PF@%d', d);
            margin_val = 100 * (mean(a2c_val) - mean(ref_val)) / mean(ref_val);
            
            line = sprintf('    %4s | %4s | %5.2f %5.2f |    %+5.1f [%+5.1f,%+5.1f] |  %+5.2f  %3d  %+5.2f\n', ...
                           cond_str, schemes{k_idx}, mean(a2c_val), mean(ref_val), ...
                           margin_val, ci(1), ci(2), dz, round(win_rate), r_rb);
            output_txt = [output_txt line];
        end
        output_txt = [output_txt sprintf('--------------------------------------------------------------------------------------------\n')];
    end
    
    % Save to effectsizes_bootstrap_v6.txt
    out_file = fullfile(here, 'effectsizes_bootstrap_v6.txt');
    fid = fopen(out_file, 'w');
    fprintf(fid, '%s', output_txt);
    fclose(fid);
    
    % Print to console
    fprintf('\nRecalculation complete. Saved to %s:\n\n', out_file);
    fprintf('%s', output_txt);
end

% ===== Helper functions for Spearman correlation without Toolbox Dependency =====
function r = rank_vector(x)
    [~, idx] = sort(x);
    r = zeros(size(x));
    r(idx) = 1:numel(x);
    [u, ~, ic] = unique(x);
    if numel(u) < numel(x)
        for i = 1:numel(u)
            ties = (ic == i);
            if sum(ties) > 1
                r(ties) = mean(r(ties));
            end
        end
    end
end

function rho = spearman_rank_corr(x, y)
    rx = rank_vector(x);
    ry = rank_vector(y);
    mx = mean(rx); my = mean(ry);
    dx = rx - mx; dy = ry - my;
    rho = sum(dx .* dy) / sqrt(sum(dx.^2) * sum(dy.^2) + eps);
end
