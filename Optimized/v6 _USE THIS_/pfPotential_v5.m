function p = pfPotential_v5(sent_cqi, bler_true, env)
% pfPotential_v5  Scheduler-visible potential rate (audit fix: no genie PF).
%
%   'reported' (default): potential rate = TBS implied by the REPORTED CQI.
%       This is all a real MAC scheduler can know at grant time; it does NOT
%       see the true instantaneous BLER.
%   'oracle'  : legacy v5.0-v5.2 behaviour, pot = (1-BLER_true)*TBS. This
%       leaks true CSI into the scheduler: PF then avoids exactly the TTIs
%       where a transmission would fail, which (a) inflates PF-scheduled
%       throughput for every scheme, (b) differentially shields AGGRESSIVE
%       policies from their own errors (their NACKs simply never happen),
%       and (c) lets any outer-loop offset ratchet upward unopposed. Found
%       via the OLLA audit (warm-started OLLA reached +164% vs baseline,
%       far beyond the genie link-adaptation ceiling - impossible unless
%       the scheduler itself was the genie).
%
%   Set env.pf_metric = 'oracle' only to reproduce pre-audit numbers.

    if isfield(env, 'pf_metric') && strcmpi(env.pf_metric, 'oracle')
        p = (1 - bler_true) * tbsFromMCSandRB(sent_cqi - 1, env.total_RB) * 1e-3;
    else
        p = tbsFromMCSandRB(sent_cqi - 1, env.total_RB) * 1e-3;
    end
end
