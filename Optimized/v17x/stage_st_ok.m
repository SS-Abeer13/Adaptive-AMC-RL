function stage_st_ok(ctx)
% Self-test: three checkpointed units. A rerun must skip all three.
    for k = 1:3
        v = ctx.unit(sprintf('unit%d', k), @() work(k));
        ctx.hbf(sprintf('st_ok got %d', v));
    end
end
function v = work(k)
    pause(0.05); v = k * 10;
end
