// hart 0: awaitingRetire = _T_523 (set under _T_526, a term of busyAll_0)
bind RD2ZynqTop p2b_assoc_chk_h0 assoc_h0 (.clock(clock), .reset(reset), .aw_soc(_T_523), .isFetch(harts_io_obs_isFetch),
  .reqFire(harts_io_physObs_reqFire), .respFire(harts_io_physObs_respFire), .commitValid(harts_io_obs_commitValid),
  .trapValid(harts_io_obs_trapValid), .trapInterrupt(harts_io_obs_trapInterrupt), .commitPc(harts_io_obs_commitPc),
  .trapEpc(harts_io_obs_trapEpc));
// hart 1: awaitingRetire = _T_599 (set under _T_602, a term of busyAll_1)
bind RD2ZynqTop p2b_assoc_chk_h1 assoc_h1 (.clock(clock), .reset(reset), .aw_soc(_T_599), .isFetch(harts_1_io_obs_isFetch),
  .reqFire(harts_1_io_physObs_reqFire), .respFire(harts_1_io_physObs_respFire), .commitValid(harts_1_io_obs_commitValid),
  .trapValid(harts_1_io_obs_trapValid), .trapInterrupt(harts_1_io_obs_trapInterrupt), .commitPc(harts_1_io_obs_commitPc),
  .trapEpc(harts_1_io_obs_trapEpc));
