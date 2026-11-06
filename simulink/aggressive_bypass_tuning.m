function C = aggressive_bypass_tuning(P, C, tau_f)
%AGGRESSIVE_BYPASS_TUNING Tightest recommended feedback tuning of the bypass-only loop.
%   C = aggressive_bypass_tuning(P, C, tau_f)
%   Reference case for the trip comparison: how far can feedback alone go?
%   - loop designed on the bypass (faster actuator than the vanes: tau 0.3 s instead of 1 s)
%   - plant after the trip: turbine isolated, header self-regulation from the choked bypass
%   - SIMC "tight" setting tau_c = theta (Skogestad: tightest recommendation, GM ~ 3, PM ~ 47 deg)
%   - optional lighter PV filter tau_f (more noise reaches the valves)
C.tau_f = tau_f;
L = bypass_loop_model(P, C);
C.tau_c_bp = L.theta;                                    % SIMC tight
C.Kp_bp = L.tau1e / (L.K * (C.tau_c_bp + L.theta));
C.Ti_bp = min(L.tau1e, 4 * (C.tau_c_bp + L.theta));
C.Tt_bp = C.Ti_bp;
C.lin_bp = L;
end
