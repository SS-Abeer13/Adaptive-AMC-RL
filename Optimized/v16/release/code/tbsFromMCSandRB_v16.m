function TBS = tbsFromMCSandRB_v16(mcs, rb)
% tbsFromMCSandRB_v16  Lookup TBS for given MCS (0..14) and RB count (1..110).
% Drop-in, bit-identical replacement for tbsFromMCSandRB that accepts
% vector mcs / rb (same size, or one scalar) and returns a vector (P0.2
% vectorisation) instead of forcing a per-user loop at the call site.
    persistent tbsTable
    if isempty(tbsTable)
        tbsTable = createTBS_Table();
    end
    rb  = max(1, min(110, round(rb)));
    mcs = max(0, min(14, round(mcs)));
    TBS = tbsTable(sub2ind(size(tbsTable), mcs + 1, rb));
end
