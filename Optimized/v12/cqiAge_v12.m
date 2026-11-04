function age = cqiAge_v12(T, N, P)
% cqiAge_v12  TTIs since the last CQI report arrived (T x N), for reporting
% period P and a deterministic per-user phase. age = 0 for P = 1.
    if P <= 1, age = zeros(T, N); return; end
    ph = mod(7 * (1:N), P);
    age = mod(((1:T).' - 1) - ph, P);
    age = min(age, (1:T).' - 1);          % no report before t = 1
end
