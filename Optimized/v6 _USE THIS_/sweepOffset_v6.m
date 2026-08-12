function sweepOffset_v6(opts)
% sweepOffset_v6  Evaluates performance of standard [-2, 2] vs. expanded [-3, 3] action offsets.
%
%   sweepOffset_v6()                         % Default budget (3 seeds, 20 traces)
%   sweepOffset_v6(struct('n_seeds', 5, 'n_eval', 30)) % Full camera-ready budget

    if nargin < 1, opts = struct(); end
    if ~isfield(opts, 'n_seeds'), opts.n_seeds = 3; end
    if ~isfield(opts, 'n_eval'),  opts.n_eval = 20; end
    if ~isfield(opts, 'N'),       opts.N = 10; end
    if ~isfield(opts, 'cqi_delay'), opts.cqi_delay = 4; end

    % Guard against under-powered runs (audit fix: an earlier call with
    % 1 seed / 2 traces / ep_deep=5 produced an invalid fig18 artifact).
    if opts.n_seeds < 2 || opts.n_eval < 10 || ...
       (isfield(opts,'ep_deep') && ~isempty(opts.ep_deep) && opts.ep_deep < 300) || ...
       (isfield(opts,'ep_tab')  && ~isempty(opts.ep_tab)  && opts.ep_tab  < 300)
        error(['sweepOffset_v6: budget too small for a reportable result ', ...
               '(need n_seeds>=2, n_eval>=10, ep>=300). Toy runs produced ', ...
               'the invalid "+16.3%%" artifact - refusing to repeat that.']);
    end

    fprintf('\n===== sweepOffset_v6: Standard vs. Expanded Actions =====\n');

    % 1. Standard actions: [-2, -1, 0, 1, 2]
    fprintf('\nRunning standard action offsets: [-2, -1, 0, 1, 2]\n');
    o_std = opts;
    o_std.actions = [-2, -1, 0, 1, 2];
    o_std.tag = 'offsetStd';
    res_std = runComparison_v6(23, o_std);

    % 2. Expanded actions: [-3, -2, -1, 0, 1, 2, 3]
    fprintf('\nRunning expanded action offsets: [-3, -2, -1, 0, 1, 2, 3]\n');
    o_exp = opts;
    o_exp.actions = [-3, -2, -1, 0, 1, 2, 3];
    o_exp.tag = 'offsetExp';
    res_exp = runComparison_v6(23, o_exp);

    % Save data (collision-proof: never overwrite an existing summary)
    here = fileparts(mfilename('fullpath'));
    outdir = here;
    if exist(fullfile(here,'Dataset'), 'dir'), outdir = fullfile(here,'Dataset'); end
    sp = fullfile(outdir, 'sweepOffset_v6_results.mat');
    if exist(sp, 'file')
        sp = fullfile(outdir, sprintf('sweepOffset_v6_results_%s.mat', datestr(now,'yyyymmdd_HHMMSS')));
    end
    save(sp, 'res_std', 'res_exp');
    fprintf('  Saved: %s\n', sp);
    
    % Plot results
    schemes = {'Baseline', 'OLLA', 'QL v6', 'Tab AC v6', 'Deep A2C v6'};
    K = numel(schemes);
    tp_std = zeros(1, K); tp_exp = zeros(1, K);
    
    M_std = res_std.metrics(1); % PF scheduler
    M_exp = res_exp.metrics(1);
    
    for k = 1:K
        tp_std(k) = mean(M_std.cell_tp{k}(:));
        tp_exp(k) = mean(M_exp.cell_tp{k}(:));
    end
    
    figure('Color','w','Position',[100 100 800 450],'Name','v6 Action Offset Expansion Sweep');
    bar_data = [tp_std; tp_exp]';
    b = bar(bar_data);
    b(1).FaceColor = [0.20 0.45 0.75]; % standard
    b(2).FaceColor = [0.10 0.65 0.20]; % expanded
    
    grid on;
    ylabel('Cell Throughput (Mbps)', 'FontSize', 11);
    set(gca, 'XTickLabel', schemes, 'XTickLabelRotation', 20, 'FontSize', 10);
    legend({'Standard Actions [-2, 2]', 'Expanded Actions [-3, 3]'}, 'Location', 'northwest', 'FontSize', 10);
    title(sprintf('Cell Throughput: Standard vs. Expanded Actions (N=%d, delay=%d)', opts.N, opts.cqi_delay), ...
          'FontWeight', 'bold', 'FontSize', 12);
          
    % Print summary
    fprintf('\n======================================================\n');
    fprintf('  SUMMARY: Offset Expansion (PF, N=%d, delay=%d)\n', opts.N, opts.cqi_delay);
    fprintf('------------------------------------------------------\n');
    for k = 1:K
        fprintf('  %-11s | Std: %5.2f Mbps | Exp: %5.2f Mbps | Change: %+5.1f%%\n', ...
                schemes{k}, tp_std(k), tp_exp(k), 100*(tp_exp(k)-tp_std(k))/max(tp_std(k), eps));
    end
    fprintf('======================================================\n\n');
end
