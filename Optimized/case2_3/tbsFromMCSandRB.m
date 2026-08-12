function TBS = tbsFromMCSandRB(mcs, rb)
% Lookup TBS for given MCS (0..14) and RB count (1..110).
% Uses a persistent copy of createTBS_Table() so repeated calls are cheap.

    persistent tbsTable
    if isempty(tbsTable)
        tbsTable = createTBS_Table();
    end
    rb  = max(1, min(110, round(rb)));
    mcs = max(0, min(14, round(mcs)));
    TBS = tbsTable(mcs + 1, rb);
end
