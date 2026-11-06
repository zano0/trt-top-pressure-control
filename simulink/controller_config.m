function C = controller_config(P)
%CONTROLLER_CONFIG Configuration and tuning of the TRT control logic (PLC, Ts = 100 ms).
%   C = controller_config(P)
%   Tuning of PIC-100 by SIMC rules on the linearised two-volume plant at the design point
%   (control narrative §4.2). All numbers are derived from params.m; only tau_c is a design choice.

C.Ts    = P.Ts;
C.p_atm = P.p_atm;
C.sp    = P.ptop_sp_g / 1e5;            % [barg] PIC-100 set point
C.p_H   = P.lim.ptop_H / 1e5;           % [barg]
C.p_HH  = P.lim.ptop_HH / 1e5;          % [barg] group P1: bypass fully open
C.m_des = P.mdot_des;                   % [kg/s] 100 % flow reference
C.P     = P;                            % design data used by the PLC (valve and turbine models)

%% Linearised plant at the design point (RUNNING, SPLIT mapping, OP in %, pressure in bar)
%   States p1 (top, V1) and p2 (header, V2); input OP (vanes); output p1.
%   C1 dp1/dt = -gc p1 + gc p2 + dm_in
%   C2 dp2/dt =  gc p1 - (gc + gt) p2 - b OP
gc = P.mdot_des / (2 * P.dp_clean_des);                     % [kg/s/Pa] cleaning, d(m_c)/d(dp)
[m1, ~] = trt_flow(P.alpha_des, 1, P.ph_des + 1, P.pout, P.T_in, P);
gt = m1 - P.mdot_des;                                       % [kg/s/Pa] turbine + ESD self-regulation
b  = P.mdot_des / P.alpha_des * (2 / 100);                  % [kg/s per % OP]
A  = [-gc / P.C1, gc / P.C1; gc / P.C2, -(gc + gt) / P.C2];
B  = [0; -b / P.C2];
lam  = sort(eig(A));                                        % [fast; slow] (both negative)
Kdc  = -[1 0] * (A \ B) / 1e5;                             % [bar per % OP] steady-state gain (sign: OP up -> p down)
tau1 = -1 / lam(2);  tau2 = -1 / lam(1);                    % dominant and second time constant
C.tau_f = 1.0;                                              % [s] PV filter on the voted top pressure
theta0  = P.vane.tau + P.pt.tau + C.tau_f + P.Ts / 2;       % [s] lags + sampling as dead time
% SIMC half rule: half of the second time constant goes to the dominant lag, half to the dead time
tau1e = tau1 + tau2 / 2;   thetae = theta0 + tau2 / 2;
C.lin = struct('gc', gc, 'gt', gt, 'b', b, 'tau1', tau1, 'tau2', tau2, 'K', abs(Kdc), ...
               'tau1e', tau1e, 'theta', thetae);

%% PIC-100 tuning: SIMC (Skogestad), lag-dominant first-order + dead time
C.tau_c = 6.0;                                              % [s] desired closed-loop time constant
C.Kp    = tau1e / (abs(Kdc) * (C.tau_c + thetae));           % [% OP per bar]
C.Ti    = min(tau1e, 4 * (C.tau_c + thetae));                % [s]
C.Tt    = C.Ti;                                              % [s] back-calculation time constant
C.kp_bp_factor = 2.0;   % gain scheduling: bypass-only mapping has half the actuator gain (§4.2)
C.Kp_bp = C.Kp * C.kp_bp_factor;   % [% OP per bar] BYPASS_ONLY mapping (same closed loop as SPLIT)
C.Ti_bp = C.Ti;                    % [s]
C.Tt_bp = C.Ti_bp;                 % [s]

%% Selectors and sequence (phase 3 subset of FB_TRT_Sequence)
C.vane_rate = 5.0;      % [%/s] PY-101 rate limit
C.load_rate = 0.5;      % [%/s] loading ramp of the vanes
C.load_bp_done = 2.0;   % [% flow] bypass "closed" threshold to finish loading
C.load_hold    = 10;    % [s]  time below threshold before RUNNING
C.load_ff      = 1;     % flow-transfer feedforward during LOADING (bypass closes by the estimated TRT flow increase)

%% Trip feedforward (PY-201)
C.ff_enable = 1;        % 1 = feedforward + output tracking, 0 = feedback only
C.kFF       = 1.0;      % [-]  feedforward gain
C.t_track   = 2.0;      % [s]  output tracking time after the FF step
C.t_fast    = 10;       % [s]  positioner fast-stroke window after a trip

%% Initial state (overwritten by steady_state.m for each scenario)
C.init = struct('state', 6, 'mapping', 1, 'vane', 80, 'op', 40, 'm_trt', P.mdot_des, ...
                'cmd', [80; 0; 0; 1; 1; 1; 1; 0; 0]);
end
