function K = compute_kpis(R, t_ev, P, C)
%COMPUTE_KPIS Performance indicators of one scenario (control narrative §11, brief §2.3).
dt  = R.t(2) - R.t(1);
k   = R.t >= t_ev;
dev = R.p_top - C.sp;                              % true top pressure (not the noisy measurement)
K.max_dev_bar  = max(abs(dev(k)));
K.max_dev_pct  = 100 * K.max_dev_bar / C.sp;       % % of set point in barg
K.IAE_bar_s    = sum(abs(dev(k))) * dt;
K.std_mbar     = 1e3 * std(dev(k));
out = find(abs(dev) > 0.01 & k, 1, 'last');        % recovery into a +/-10 mbar band
if isempty(out), K.t_rec_s = 0; else, K.t_rec_s = max(R.t(out) - t_ev, 0); end
K.bypass_Nm3   = sum(R.m_bp(k)) * dt / P.rho_N;
w_spec = P.Pel_des / P.mdot_des;                   % [J/kg] electrical energy per kg through the TRT
K.E_lost_MWh   = sum(R.m_bp(k)) * dt * w_spec / 3.6e9;
K.P_el_mean_MW = mean(R.P_el(k));
K.vane_travel_pct = sum(abs(diff(R.alpha(k))));
K.bp_travel_pct   = sum(abs(diff(R.thA(k)))) + sum(abs(diff(R.thB(k))));
K.n_max_rpm    = max(R.n);
end
