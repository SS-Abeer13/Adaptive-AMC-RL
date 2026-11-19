function res = eval_pfdiag_eot(case_tag, n_eval, ctx)
% eval_pfdiag_eot  D-PF diagnostic for M2 or M4.
% Evaluates policies and comparators under:
%   1. env.pf_avg = 'scheduled' (asserts exact match against stored results)
%   2. env.pf_avg = 'acked' (training definition)
% Reports margin vs comparators and Holm p-values under both definitions.

    here = fileparts(mfilename('fullpath'));
    v17x_dir = fileparts(here);
    v17_dir = fullfile(fileparts(v17x_dir), 'v17');
    addpath(here); addpath(v17x_dir); addpath(v17_dir);
    v17_setup;

    ctx.hbf(sprintf('eval_pfdiag_eot: starting %s, n_eval=%d', case_tag, n_eval));

    switch upper(case_tag)
        case 'M2'
            tag = 'M2_dl_rtt0';
        case 'M4'
            tag = 'M4_gp_rtt0';
        otherwise
            error('Unknown case_tag: %s', case_tag);
    end

    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile(v17_dir, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R = data.results;
    env = R.env;
    env.scheduler = 'pf';
    b0 = min(env.burn_in, o.simTime - 1);
    N = env.N;

    % Set of schemes in R
    schemes = R.schemes;
    n_schemes = numel(schemes);

    % Pre-generate traces
    traces = struct('SINR', {}, 'obsS', {}, 'meta', {}, 'U', {});
    for j = 1:n_eval
        tr_seed = ov.trace_seed_base + j;
        crn_seed = ov.crn_seed_base + j;
        rng(tr_seed, 'twister'); [Strue, ~, meta] = generateChannel_v17(o.simTime, env);
        obsS = cqiFeedback_v17(Strue, env, meta.delays);
        meta.trace_id = j;
        rng(crn_seed, 'twister'); U = rand(o.simTime, N);
        traces(j).SINR = Strue; traces(j).obsS = obsS; traces(j).meta = meta; traces(j).U = U;
    end

    modes = {'scheduled', 'acked'};
    res = struct('case_tag', case_tag, 'n_eval', n_eval, 'schemes', {schemes});

    for m_idx = 1:numel(modes)
        pf_mode = modes{m_idx};
        ctx.hbf(sprintf('eval_pfdiag_eot: %s with pf_avg=%s', case_tag, pf_mode));
        env_mode = env;
        env_mode.pf_avg = pf_mode;
        env_mode.eot_mode = 'asrun';

        vals_all = cell(1, n_schemes);

        for k = 1:n_schemes
            s_name = schemes{k};
            % Map scheme to ptype and policy
            [ptype, polSrc, fixed_off] = map_scheme(s_name);
            envE = env_mode;
            if ~isnan(fixed_off), envE.fixed_offset = fixed_off; end

            ns = 1;
            if any(strcmp(polSrc, {'A2C', 'A2Cbest', 'A2CResid800', 'BanditG', 'BanditD'}))
                ns = 10;
            end

            vals_k = zeros(ns, n_eval);

            for s = 1:ns
                pol = [];
                switch polSrc
                    case 'A2C'
                        pol = R.policies.A2C{s};
                    case 'A2Cens'
                        pol = R.policies.A2C;
                    case 'A2Cbest'
                        pol = R.policies.A2Cbest{s};
                    case 'A2CResid800'
                        ckpt_file = fullfile(v17_dir, 'Dataset', 'ckpt', sprintf('%s_seed%d.mat', tag, s));
                        s_ck = load(ckpt_file);
                        pol = s_ck.ar800;
                    case 'BanditG'
                        if iscell(R.policies.Bandit)
                            pol = R.policies.Bandit{s};
                        else
                            pol = R.policies.Bandit;
                        end
                    case 'BanditD'
                        if iscell(R.policies.BanditD)
                            pol = R.policies.BanditD{s};
                        else
                            pol = R.policies.BanditD;
                        end
                    case ''
                        pol = [];
                end

                for j = 1:n_eval
                    rng(77000 + 100*j + 10*k + s);
                    [tp, ~, ~, ~, inf] = evalPolicy_g6_eot(ptype, pol, traces(j).SINR, traces(j).obsS, envE, traces(j).meta, traces(j).U);
                    [~, ~, v] = userMetric_v17(envE, tp, inf, b0);
                    vals_k(s, j) = v;

                    if strcmp(pf_mode, 'scheduled')
                        stored_v = R.metrics.primary{k}(s, j);
                        diff = abs(v - stored_v);
                        if diff > 1e-9
                            error('D_PF:scheduled_repro_fail', ...
                                'D-PF REPRO FAIL: %s scheme %s (s=%d, j=%d) computed=%.6f, stored=%.6f, diff=%g', ...
                                case_tag, s_name, s, j, v, stored_v, diff);
                        end
                    end
                end
            end
            vals_all{k} = vals_k;
        end
        res.(pf_mode) = vals_all;
    end
end

function [ptype, polSrc, fixed_off] = map_scheme(s_name)
    fixed_off = NaN;
    switch s_name
        case 'Baseline'
            ptype = 'baseline'; polSrc = '';
        case 'OLLA'
            ptype = 'olla'; polSrc = '';
        case 'OLLA (tuned target)'
            ptype = 'olla_tuned'; polSrc = '';
        case 'Multi-OLLA'
            ptype = 'multi_olla'; polSrc = '';
        case 'Fixed'
            ptype = 'fixed'; polSrc = '';
        case 'FixedPU (Oracle)'
            ptype = 'fixed_class'; polSrc = '';
        case 'Context table'
            ptype = 'ctxtab'; polSrc = '';
        case 'Deep A2C v17'
            ptype = 'a2c_v17'; polSrc = 'A2C';
        case 'Deep A2C v17 (best-on-val)'
            ptype = 'a2c_v17'; polSrc = 'A2Cbest';
        case 'Deep A2C v17 (ensemble)'
            ptype = 'a2c_ens'; polSrc = 'A2Cens';
        case 'Deep A2C v17 (resid-800)'
            ptype = 'a2c_v17'; polSrc = 'A2CResid800';
        case 'Bandit (global)'
            ptype = 'bandit'; polSrc = 'BanditG';
        case 'Bandit (delay class)'
            ptype = 'bandit'; polSrc = 'BanditD';
        otherwise
            error('Unknown scheme name: %s', s_name);
    end
end
