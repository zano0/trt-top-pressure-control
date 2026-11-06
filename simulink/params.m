%% params.m - Design point and model parameters for the TRT top-pressure control project
%
% Single numerical source of truth for the Simulink model, the scenario
% scripts and docs/assumptions.md. All values are ILLUSTRATIVE (public
% literature / engineering estimates); see docs/assumptions.md for sources.
%
% Convention: SI units inside the model (Pa, kg/s, K, W). Pressures are
% ABSOLUTE in every equation; barg values are given only as inputs/reporting.
%
% Usage:  P = params();        % returns struct P, prints nothing
%         params('report');    % also prints the design-point check

function P = params(mode)
if nargin < 1, mode = ''; end

%% 1. Constants and gas properties (blast-furnace gas, dry cleaning)
P.p_atm   = 1.01325e5;        % [Pa]    standard atmosphere (barg -> bar a)
P.T_N     = 273.15;           % [K]     normal conditions for Nm3
P.R_univ  = 8.314462;         % [J/mol/K]
P.M_gas   = 0.030;            % [kg/mol] ~ 50% N2, 22% CO, 22% CO2, 4% H2 (typical BF gas)
P.R_s     = P.R_univ / P.M_gas;          % [J/kg/K]  ~277
P.rho_N   = P.p_atm / (P.R_s * P.T_N);   % [kg/Nm3]  ~1.34
P.cp      = 1050;             % [J/kg/K]
P.k       = P.cp / (P.cp - P.R_s);   % [-]   isentropic exponent, ideal-gas consistent (~1.36)
P.kexp    = (P.k - 1) / P.k;  % [-]     exponent in the isentropic work term

%% 2. Design point (brief section 1.2)
P.Q_N_des   = 280000;                       % [Nm3/h] top-gas flow
P.mdot_des  = P.Q_N_des * P.rho_N / 3600;   % [kg/s]  ~104
P.ptop_sp_g = 1.8e5;                        % [Pa g]  top-pressure set point
P.ptop_des  = P.ptop_sp_g + P.p_atm;        % [Pa a]
P.dp_clean_des = 0.20e5;                    % [Pa]    gas-cleaning dp at design flow
P.dp_esd_des   = 0.05e5;                    % [Pa]    dp across open ESD XV-101 + inlet piping
P.pout_g    = 0.10e5;                       % [Pa g]  plant gas network
P.pout      = P.pout_g + P.p_atm;           % [Pa a]  (stiff network, held constant)
P.T_in      = 120 + 273.15;                 % [K]     turbine inlet temperature TT-101
P.eta_is    = 0.85;                         % [-]     turbine isentropic efficiency
P.eta_mech  = 0.98;                         % [-]     bearings, gearbox-less direct drive
P.eta_gen   = 0.97;                         % [-]     generator efficiency
P.hours_yr  = 8000;                         % [h/yr]  TRT availability

% Quadratic pressure-drop coefficients: dp = k * mdot^2
P.k_clean = P.dp_clean_des / P.mdot_des^2;  % [Pa/(kg/s)^2]
P.k_esd   = P.dp_esd_des   / P.mdot_des^2;  % [Pa/(kg/s)^2]

% Pressures along the train at the design point
P.ph_des  = P.ptop_des - P.dp_clean_des;    % [Pa a] header (clean gas)
P.pin_des = P.ph_des   - P.dp_esd_des;      % [Pa a] turbine inlet
P.PR_des  = P.pin_des / P.pout;             % [-]    expansion ratio

% Power chain
P.dh_is_des = P.cp * P.T_in * (1 - (P.pout / P.pin_des)^P.kexp);  % [J/kg] isentropic enthalpy drop
P.Pturb_des = P.eta_is * P.mdot_des * P.dh_is_des;                % [W]   shaft power
P.Ploss_des = (1 - P.eta_mech) * P.Pturb_des;                     % [W]   mechanical losses at 100% speed
P.Pel_des   = (P.Pturb_des - P.Ploss_des) * P.eta_gen;            % [W]   electrical power
P.E_yr_GWh  = P.Pel_des * P.hours_yr / 1e9;                       % [GWh/yr]

%% 3. Turbine: Stodola ellipse law  mdot = K * g(alpha) * sqrt((pin^2 - pout^2)/T_in)
% g(alpha) = alpha (effective nozzle area proportional to vane opening):
% simplification, real vane characteristics are mildly non-linear.
P.alpha_des = 0.80;           % [-] design vane opening: 20% margin for flow increases
P.K_stod    = P.mdot_des / (P.alpha_des * sqrt((P.pin_des^2 - P.pout^2) / P.T_in));
P.mdot_trt_max = P.K_stod * 1.0 * sqrt((P.pin_des^2 - P.pout^2) / P.T_in); % at alpha = 1

%% 4. Bypass / septum valves PV-201A/B: ISA-75.01 (IEC 60534-2-1) compressible flow
% W [kg/h] = N6 * Fp * Kv * f(theta) * Y * sqrt(x * p1[bar] * rho1),  N6 = 27.3 (Kv units)
% x = dp/p1, limited to x_choked = Fk * xT;  Y = 1 - x/(3 Fk xT), Y = 2/3 when choked.
P.bp.N6       = 27.3;         % [-]   ISA-75.01 constant for Kv, kg/h, bar, kg/m3
P.bp.Fp       = 1.0;          % [-]   no reducers (simplification)
P.bp.xT       = 0.45;         % [-]   high-performance butterfly, near full open
P.bp.Fk       = P.k / 1.4;    % [-]   specific-heat-ratio factor
P.bp.R        = 30;           % [-]   inherent rangeability, equal-percentage trim
P.bp.share    = 0.60;         % [-]   each valve passes 60% of design flow fully open
P.bp.n        = 2;            % [-]   PV-201A and PV-201B
p1_bar   = P.ph_des / 1e5;
rho1     = P.ph_des / (P.R_s * P.T_in);
x_des    = (P.ph_des - P.pout) / P.ph_des;
x_ch     = P.bp.Fk * P.bp.xT;
x_eff    = min(x_des, x_ch);
Y_des    = 1 - x_eff / (3 * x_ch);
W_req    = P.bp.share * P.mdot_des * 3600;                      % [kg/h] per valve at 100% travel
P.bp.Kv  = W_req / (P.bp.N6 * P.bp.Fp * Y_des * sqrt(x_eff * p1_bar * rho1)); % [m3/h] per valve
P.bp.x_des = x_des;  P.bp.x_choked = x_ch;  P.bp.choked_des = x_des >= x_ch;
% Inherent characteristic, zero at closed: f(theta) = (R^theta - 1)/(R - 1)
% implemented in bp_flow.m / bp_position.m (no function handles: P is a Simulink parameter)

%% 5. Equivalent gas volume V (physical estimate, NOT tuned for a time constant)
P.V_parts = struct( ...
    'furnace_top_dome',  500, ...   % [m3] free volume above stock line, ~3000 m3 inner-volume BF
    'uptakes_downcomer', 400, ...   % [m3] uptakes, downcomer, dirty-gas main
    'dust_catcher',     1200, ...   % [m3] ~ D 11 m x H 15 m effective
    'bag_filters',      1500, ...   % [m3] ~ 10 vessels x 150 m3 (dirty + clean side)
    'clean_gas_mains',   400);      % [m3] clean-gas header up to TRT / septum station
P.V = sum(cell2mat(struct2cell(P.V_parts)));                             % [m3] ~4000
P.C_gas = P.V / (P.R_s * P.T_in);                               % [kg/Pa] gas capacitance
% Two-volume split around the gas-cleaning resistance (top pressure has its own dynamics):
%   V1 = furnace top + uptakes + dust catcher + dirty side of the filters  (measured by PT-100A/B/C)
%   V2 = clean side of the filters + clean-gas mains                        (measured by PT-110)
P.V1 = P.V_parts.furnace_top_dome + P.V_parts.uptakes_downcomer + P.V_parts.dust_catcher ...
       + 0.5 * P.V_parts.bag_filters;                          % [m3] ~2850
P.V2 = 0.5 * P.V_parts.bag_filters + P.V_parts.clean_gas_mains; % [m3] ~1150
P.C1 = P.V1 / (P.R_s * P.T_in);                                 % [kg/Pa]
P.C2 = P.V2 / (P.R_s * P.T_in);                                 % [kg/Pa]
P.M_stored = P.C_gas * P.ph_des;                                % [kg]
% Open-loop time constant, vanes frozen, bypass closed (linearised Stodola + ESD dp)
dm_dp = P.mdot_des * P.pin_des / (P.pin_des^2 - P.pout^2);      % [kg/s/Pa] d(mdot)/d(pin)
P.tau_ol = P.C_gas / dm_dp;                                     % [s]  (ESD dp effect neglected)

%% 6. Rotor (two modes, explicit switch on CB-101)
P.n_nom    = 3000;                    % [rpm] 2-pole generator, 50 Hz, direct drive
P.w_nom    = P.n_nom * 2*pi / 60;     % [rad/s]
P.S_gen    = 9e6;                     % [VA]  generator rating (P_el / 0.8 pf)
P.H_inert  = 1.2;                     % [s]   inertia constant turbine + generator
P.J        = 2 * P.H_inert * P.S_gen / P.w_nom^2;   % [kg m2]
P.Ek_nom   = 0.5 * P.J * P.w_nom^2;   % [J]   kinetic energy at nominal speed
% Mechanical losses scale with speed^2 (windage + bearing friction), matched at 100% speed
P.c_loss   = P.Ploss_des / P.w_nom^2; % [W/(rad/s)^2]

%% 7. Actuators and instruments
P.Ts        = 0.1;    % [s]   controller / PLC sample time
P.dt_sim    = 0.01;   % [s]   fixed solver step (ode4)
P.vane.tau  = 1.0;    % [s]   positioner first-order lag
P.vane.rate = 0.05;   % [1/s] normal stroke rate limit (20 s full stroke)
P.vane.rate_trip = 1/3;   % [1/s] quick close on trip (3 s full stroke)
P.bpv.tau   = 0.3;    % [s]   positioner lag
P.bpv.rate  = 0.10;   % [1/s] regulating stroke rate (10 s full stroke)
P.bpv.rate_fast = 1/1.5;  % [1/s] fast-opening solenoid path (1.5 s full stroke)
P.esd.t_close = 0.7;  % [s]   XV-101 closing time (sensitivity 0.5 - 1.0 s)
P.esd.t_open  = 10;   % [s]   XV-101 opening time (slow, start-up only)
P.esd.phi_exp = 2;    % [-]   ESD flow-area law phi = x^n (butterfly: flow cut mostly near closure)
P.esd.x_closed = 0.02;% [-]   ZSC-101 switching point
P.pt.tau    = 0.2;    % [s]   PT-100A/B/C transmitter + impulse line lag
P.pt.sigma  = 0.002e5;% [Pa]  measurement noise (1 sigma), ~0.05% of 0-4 barg span
P.pt.range  = [0 4e5];% [Pa g] transmitter calibrated range

%% 8. Trip / alarm thresholds (to be aligned with tags.csv)
P.lim.speed_HH = 1.10 * P.n_nom;   % [rpm] overspeed trip
P.lim.ptop_H   = P.ptop_sp_g + 0.10e5; % [Pa g] alarm
P.lim.ptop_HH  = P.ptop_sp_g + 0.20e5; % [Pa g] bypass full open
P.lim.bleeder  = P.ptop_sp_g + 0.40e5; % [Pa g] mechanical bleeders (not in PLC)

%% Report
if strcmpi(mode, 'report')
    fprintf('\n=== TRT design point check ===\n');
    fprintf('Gas: R_s = %.1f J/kg/K, rho_N = %.3f kg/Nm3\n', P.R_s, P.rho_N);
    fprintf('Flow: %.0f Nm3/h = %.1f kg/s\n', P.Q_N_des, P.mdot_des);
    fprintf('p_top = %.3f bar a (%.2f barg)\n', P.ptop_des/1e5, P.ptop_sp_g/1e5);
    fprintf('p_h   = %.3f bar a, p_in = %.3f bar a, p_out = %.3f bar a\n', P.ph_des/1e5, P.pin_des/1e5, P.pout/1e5);
    fprintf('Expansion ratio = %.3f\n', P.PR_des);
    fprintf('dh_is = %.1f kJ/kg\n', P.dh_is_des/1e3);
    fprintf('P_turb = %.2f MW, P_el = %.2f MW, E = %.1f GWh/yr\n', P.Pturb_des/1e6, P.Pel_des/1e6, P.E_yr_GWh);
    fprintf('Stodola K = %.4e, max TRT flow (alpha=1) = %.1f kg/s (%.0f%%)\n', P.K_stod, P.mdot_trt_max, 100*P.mdot_trt_max/P.mdot_des);
    fprintf('Bypass: x = %.3f, x_choked = %.3f, choked = %d, Kv = %.0f m3/h per valve\n', P.bp.x_des, P.bp.x_choked, P.bp.choked_des, P.bp.Kv);
    fprintf('V = %.0f m3, C = %.4f kg/Pa, stored mass = %.0f kg (%.0f s of flow)\n', P.V, P.C_gas, P.M_stored, P.M_stored/P.mdot_des);
    fprintf('Open-loop tau = %.1f s\n', P.tau_ol);
    fprintf('Rotor: J = %.0f kg m2, Ek = %.1f MJ\n', P.J, P.Ek_nom/1e6);
    % Back-of-envelope trip: imbalance mdot_des over t_unbal seconds
    for t_unbal = [5 1.5]
        fprintf('Trip estimate: %.1f s of unbalanced flow -> dp ~ %.3f bar\n', t_unbal, P.mdot_des*t_unbal/P.C_gas/1e5);
    end
    % Load rejection energy: P_turb decays linearly while ESD closes
    E_rej = 0.5 * P.Pturb_des * P.esd.t_close;
    fprintf('Load rejection: %.1f MJ into rotor -> speed rise ~ %.1f%%\n', E_rej/1e6, 100*(sqrt(1 + E_rej/P.Ek_nom) - 1));
end
end
