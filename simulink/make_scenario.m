function [SCN, T, X0, C, P, meta] = make_scenario(name, P, C)
%MAKE_SCENARIO Scenario definition: disturbance, commands, initial state and options.
%   SCN columns: t | m_in [kg/s] | mode cmd | trip cmd | grid ok | noise A B C [bar] | fault A B C [bar]
%   Every scenario uses a fixed random seed for the measurement noise.
m0 = P.mdot_des;  t_ev = 20;  kind = 'running';  alpha0 = [];
switch name
    case 'S0_steady',      T = 60;  t_ev = 0;  dist = @(t) m0 + 0*t;
    case 'S1a_step_up',    T = 200; dist = @(t) m0 * (1 + 0.10 * (t >= t_ev));
    case 'S1b_step_down',  T = 200; dist = @(t) m0 * (1 - 0.10 * (t >= t_ev));
    case 'S2_slip',        T = 150; dist = @(t) m0 * (1 + 0.30 * pulse(t, t_ev, 1, 5));
    case {'S3a_trip_ff', 'S3b_trip_noff', 'S3c_trip_pi_tight', 'S3d_trip_pi_tight_f03'}
        T = 150; dist = @(t) m0 + 0*t;
    case {'S4_loading', 'S4b_loading_noff'}
        T = 300; t_ev = 10; dist = @(t) m0 + 0*t; kind = 'loading'; alpha0 = 0.10;
    otherwise, error('Unknown scenario %s', name);
end
if strcmp(name, 'S3b_trip_noff'), C.ff_enable = 0; end
if strcmp(name, 'S3c_trip_pi_tight'),     C.ff_enable = 0; C = aggressive_bypass_tuning(P, C, 1.0); end
if strcmp(name, 'S3d_trip_pi_tight_f03'), C.ff_enable = 0; C = aggressive_bypass_tuning(P, C, 0.3); end
if strcmp(name, 'S4b_loading_noff'), C.load_ff = 0; end
[X0, C] = steady_state(P, C, kind, dist(0), alpha0);

t = (0:C.Ts:T)';  n = numel(t);
rng(1);
noise = P.pt.sigma / 1e5 * randn(n, 3);
mode  = C.init.state * ones(n, 1);
trip  = zeros(n, 1);
if startsWith(name, 'S3'), trip = double(t >= t_ev); end
SCN = [t, dist(t), mode, trip, ones(n, 1), noise, zeros(n, 3)];
meta = struct('name', name, 't_ev', t_ev, 'T', T);
end

function y = pulse(t, t0, tr, th)
% trapezoidal pulse: ramp tr, hold th, ramp tr
y = min(max((t - t0) / tr, 0), 1) .* min(max((t0 + tr + th + tr - t) / tr, 0), 1);
end
