% build_case_registry  PLAN_v16.md Stage A4 & v17: parse every
% Optimized/v*/Dataset/fill_summary_v*.txt (v9-v17) and write
% Optimized/case_registry.csv, one row per (tag, rl_scheme), with case_id.
%
% Primary source per row is the WIN| line (present in v10-v17), which
% already carries rl_scheme, primary metric, rl value, best comparator
% name/value, margin and holm_vs_best, and the WIN flag.
% For v9 (no WIN| lines), take the CMP and SCHEME lines.
% claimA/claimB come from the matching REPL| line where one exists (v12+);
% v9-v11 have no REPL| lines (no replication-style Holm/CI claim split),
% so claimA/claimB are left blank for those rows.
%
% case_id column: unique integer assigned per (version, tag) case so cases
% can be counted separately from scheme rows.

root = 'D:\Adaptive AMC A2C+QL\Optimized';
versions = {'v9', 'v10', 'v11', 'v12', 'v13', 'v14', 'v15', 'v16', 'v17'};

rows = {};
caseMap = containers.Map();
nextCaseId = 1;

for vi = 1:numel(versions)
    v = versions{vi};
    files = dir(fullfile(root, v, 'Dataset', ['fill_summary_' v '*.txt']));
    for fi = 1:numel(files)
        fname = files(fi).name;
        if contains(fname, 'backup'), continue; end
        fpath = fullfile(files(fi).folder, fname);
        txt = fileread(fpath);
        lines = strsplit(txt, {'\r\n', '\n'});

        if strcmp(v, 'v9')
            % v9 special handling: no WIN| lines, parse CONFIG, SCHEME, CMP
            tags = {};
            cfgMap = containers.Map();
            for li = 1:numel(lines)
                L = strtrim(lines{li});
                if startsWith(L, 'CONFIG|')
                    f = strsplit(L, '|');
                    tag = f{2};
                    ns = getTok(L, 'n_seeds=(\d+)');
                    ne = getTok(L, 'n_eval=(\d+)');
                    cfgMap(tag) = struct('n_seeds', ns, 'n_eval', ne);
                    if ~any(strcmp(tags, tag))
                        tags{end+1} = tag; %#ok<AGROW>
                    end
                end
            end

            for ti = 1:numel(tags)
                tag = tags{ti};
                schemes = containers.Map();
                for li = 1:numel(lines)
                    L = strtrim(lines{li});
                    if startsWith(L, ['SCHEME|' tag '|'])
                        f = strsplit(L, '|');
                        sname = f{3};
                        tpVal = getTok(L, 'tp=([-\d\.]+)');
                        if ~isempty(tpVal)
                            schemes(sname) = str2double(tpVal);
                        end
                    end
                end

                rl_scheme = 'Deep A2C v9';
                if isKey(schemes, rl_scheme)
                    rl_val = sprintf('%.4f', schemes(rl_scheme));
                else
                    rl_val = '';
                end

                bestName = '';
                bestTp = -inf;
                kList = keys(schemes);
                for ki = 1:numel(kList)
                    kName = kList{ki};
                    if ~strcmp(kName, rl_scheme) && schemes(kName) > bestTp
                        bestTp = schemes(kName);
                        bestName = kName;
                    end
                end

                pct = ''; holm = '';
                cmpPrefix = ['CMP|' tag '|A2C vs ' bestName '|'];
                for li = 1:numel(lines)
                    L = strtrim(lines{li});
                    if startsWith(L, cmpPrefix)
                        pct = getTok(L, 'pct=([-\d\.]+)');
                        holm = getTok(L, 'holm=([-\de\.]+)');
                        break;
                    end
                end

                primary = 'goodput';
                cA = ''; cB = '';
                winFlag = '0';
                nseeds = cfgMap(tag).n_seeds;
                ntr = cfgMap(tag).n_eval;
                role = infer_role_v16(v, tag);
                status = 'valid';

                caseKey = [v '||' tag];
                if ~isKey(caseMap, caseKey)
                    caseMap(caseKey) = nextCaseId;
                    nextCaseId = nextCaseId + 1;
                end
                cid = caseMap(caseKey);

                rows(end+1, :) = {cid, v, tag, role, rl_scheme, primary, rl_val, bestName, pct, cA, cB, winFlag, holm, nseeds, ntr, status}; %#ok<AGROW>
            end
            continue;
        end

        % v10-v17: has WIN| lines
        cfgMap = containers.Map();
        for li = 1:numel(lines)
            L = strtrim(lines{li});
            if startsWith(L, 'CONFIG|')
                f = strsplit(L, '|');
                tag = f{2};
                ns = getTok(L, 'n_seeds=(\d+)');
                ne = getTok(L, 'n_eval=(\d+)');
                cfgMap(tag) = struct('n_seeds', ns, 'n_eval', ne);
            end
        end

        replMap = containers.Map();
        for li = 1:numel(lines)
            L = strtrim(lines{li});
            if startsWith(L, 'REPL|')
                f = strsplit(L, '|');
                tag = f{2};
                scheme = getTok(L, 'scheme=([^|]+)');
                if isempty(scheme), continue; end
                cA = getTok(L, 'claimA_olla_family=(\d)');
                cB = getTok(L, 'claimB_calibrated_rules=(\d)');
                replMap([tag '||' scheme]) = struct('claimA', cA, 'claimB', cB);
            end
        end

        for li = 1:numel(lines)
            L = strtrim(lines{li});
            if ~startsWith(L, 'WIN|'), continue; end
            f = strsplit(L, '|');
            if numel(f) < 3, continue; end
            tag = f{2};
            % WIN| layout varies: WIN|tag|scheme|... (v11+) or WIN|tag|...
            % (v10, no explicit scheme field -- scheme is implied, "A2C").
            schemeField = f{3};
            if contains(schemeField, '=')
                scheme = 'A2C';          % v10 layout: no scheme token, primary= comes next
                rest = L;
            else
                scheme = schemeField;     % v11+ layout: explicit scheme name
                rest = L;
            end
            primary  = getTok(rest, 'primary=([^|]+)');
            rl       = getTok(rest, '\|rl=([^|]+)');
            if isempty(rl), rl = getTok(rest, '\|a2c=([^|]+)'); end  % v10 field name
            bestName = getTok(rest, 'best_simple=([^|]+)');
            pct      = getTok(rest, 'pct_vs_best=([^|]+)');
            holm     = getTok(rest, 'holm_vs_best=([^|]+)');
            winFlag  = getTok(rest, 'all_holm_lt_0\.05_and_ci_gt0=(\d)');

            key = [tag '||' scheme];
            if isKey(replMap, key)
                cA = replMap(key).claimA; cB = replMap(key).claimB;
            else
                cA = ''; cB = '';
            end
            if isKey(cfgMap, tag)
                nseeds = cfgMap(tag).n_seeds; ntr = cfgMap(tag).n_eval;
            else
                nseeds = ''; ntr = '';
            end
            role = infer_role_v16(v, tag);
            % Status column: superseded for v15 RTT>0 and v16 K1/K3/L1/L3, valid elsewhere
            if (strcmp(v, 'v15') && any(strcmp(tag, {'Z1_rtt8', 'Z2_rtt4', 'Z3_rtt8_loose'}))) || ...
               (strcmp(v, 'v16') && any(strcmp(tag, {'K1_dl_rtt8', 'K3_gp_rtt8', 'L1_dl_rtt8_long', 'L3_gp_rtt8_long'})))
                status = 'superseded: PF averaging artefact (v17)';
            else
                status = 'valid';
            end

            caseKey = [v '||' tag];
            if ~isKey(caseMap, caseKey)
                caseMap(caseKey) = nextCaseId;
                nextCaseId = nextCaseId + 1;
            end
            cid = caseMap(caseKey);

            rows(end+1, :) = {cid, v, tag, role, scheme, primary, rl, bestName, pct, cA, cB, winFlag, holm, nseeds, ntr, status}; %#ok<AGROW>
        end
    end
end

outFile = fullfile(root, 'case_registry.csv');
fid = fopen(outFile, 'w');
fprintf(fid, 'case_id,version,tag,role,rl_scheme,primary_metric,rl_value,best_rule,margin_vs_best_rule_pct,claimA,claimB,win,holm_vs_best,n_seeds,n_traces,status\n');
for i = 1:size(rows, 1)
    fprintf(fid, '%d,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n', rows{i, :});
end
fclose(fid);
fprintf('Wrote %d rows (%d unique cases) to %s\n', size(rows, 1), nextCaseId - 1, outFile);

function tok = getTok(str, pattern)
    m = regexp(str, pattern, 'tokens', 'once');
    if isempty(m), tok = ''; else, tok = m{1}; end
end

function role = infer_role_v16(v, tag)
% Best-effort role classification from each version's own README
% labeling (read in full for v12/v13/v15 in this pass; v10/v11/v14
% inferred from tag-name convention -- primary/secondary tags are the
% first-named case per version, "pre_*" and training-length/ablation
% variants default to 'ablation' per PLAN_v16.md A4's fallback rule).
    primaryTags   = {'E4c_deadline', 'R1_pf', 'X1_pf', 'Y0_base', 'Z1_rtt8', 'T1_gp', 'T1_gp_ppo', ...
                      'K1_dl_rtt8', 'K3_gp_rtt8', 'M1_dl_rtt8', 'M3_gp_rtt8', 'gp_O'};
    secondaryTags = {'R2_edf', 'X1_edf', 'X2_pf_shaped', 'Y0_noshape', 'steady_match', 'steady_cold'};
    robustnessTags = {'Z2_rtt4', 'Z3_rtt8_loose', 'Y1_lo_tight', 'Y2_lo_loose', 'Y3_hi_tight', 'Y4_hi_loose', ...
                       'K2_dl_rtt0', 'K4_gp_rtt0', 'M2_dl_rtt0', 'M4_gp_rtt0', ...
                       'rr_O', 'eq_O', 'burst6_O', 'burst12_O', 'h0_O', 'h05_O'};
    if startsWith(tag, 'pre_')
        role = 'ablation';
    elseif any(strcmp(tag, primaryTags))
        role = 'primary';
    elseif any(strcmp(tag, secondaryTags))
        role = 'secondary';
    elseif any(strcmp(tag, robustnessTags))
        role = 'robustness';
    else
        role = 'ablation';
    end
end
