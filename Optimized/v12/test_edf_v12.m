% test_edf_v12  Unit test for schedule_users_v12 (run headless; writes logs/test_edf_v12.log).
v12_setup;
lf = fullfile(v12, 'logs', 'test_edf_v12.log'); fid = fopen(lf, 'w');
ok = true;
R = [1 1 1 1]; pot = [5 9 7 0];
% 1) earliest deadline wins even with lower PF metric
rb = schedule_users_v12('edf', 1, 4, R, pot, 100, [12 15 11 3]);
ok = ok && isequal(rb, [0 0 100 0]);          % user 4 has no data (pot 0), so user 3 (dl 11)
% 2) tie on deadline -> PF metric
rb = schedule_users_v12('edf', 1, 4, R, pot, 100, [10 10 12 Inf]);
ok = ok && isequal(rb, [0 100 0 0]);
% 3) no deadline info -> PF
rb1 = schedule_users_v12('edf', 1, 4, R, pot, 100, inf(1, 4));
rb2 = schedule_users_v5('pf', 1, 4, R, pot, 100);
ok = ok && isequal(rb1, rb2);
% 4) other modes unchanged
for m = {'pf', 'rr', 'eq'}
    ok = ok && isequal(schedule_users_v12(m{1}, 3, 4, R, pot, 100, [1 2 3 4]), schedule_users_v5(m{1}, 3, 4, R, pot, 100));
end
if ok, res = 'OK'; else, res = 'FAIL'; end
fprintf(fid, 'TEST_EDF_%s\n', res); fclose(fid);
if ok, disp('TEST_EDF_OK'); else, disp('TEST_EDF_FAIL'); end
