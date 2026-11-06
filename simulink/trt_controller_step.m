function [cmd, dg] = trt_controller_step(meas, scn, C)
%TRT_CONTROLLER_STEP One 100 ms scan of the TRT control PLC (phase 3 subset).
%   [cmd, dg] = trt_controller_step(meas, scn, C)
%
%   Implements (control narrative TRT-CN-001):
%     PY-100V  2oo3 median voting (degraded modes: phase 4/5)
%     PIC-100  PI, positional, back-calculation anti-windup, output tracking, gain scheduling
%     PY-100S  SPLIT / BYPASS_ONLY mapping, bypass request in % of design flow
%     PY-101   vane selector: rate limit, loading ramp, forced close at trip
%     PY-201   flow -> position (inverse ISA-75.01), trip feedforward + output tracking
%     Trip     XV-101, vanes, sequential CB-101 trip on reverse power
%   Written for code generation (Simulink PLC Coder in phase 4): persistent state, no dynamic memory.
%
%   meas (13): 1-3 PT-100A/B/C [barg], 4 PT-110 [barg], 5 PT-300 [barg], 6 TT-101 [degC],
%              7 ZT-101 [%], 8 ZT-201A [%], 9 ZT-201B [%], 10 ZSC-101, 11 JT-101 [MW],
%              12 CB-101-ST, 13 ST-101 [rpm]
%   scn  (10): 2 mode command (5 LOADING, 6 RUNNING), 3 trip command (others: plant only)
%   cmd   (9): 1 ZY-101 [%], 2 PV-201A [%], 3 PV-201B [%], 4 XY-101, 5 XY-102, 6 XY-201A,
%              7 XY-201B, 8 CB-101-TRP, 9 bypass positioner fast stroke
%   dg    (8): 1 voted and filtered p_top [barg], 2 PIC-100 OP [%], 3 state, 4 tracking active,
%              5 mapping (1 SPLIT, 0 BYPASS_ONLY), 6 vane command [%], 7 bypass request [% flow],
%              8 estimated TRT flow [kg/s]
%#codegen

ST_LOADING = 5;  ST_RUNNING = 6;  ST_TRIP = 9;
MAP_BYPASS = 0;  MAP_SPLIT = 1;

persistent initialised I op vane_cmd state mapping track_t trip_t loaded_t cb_trp m_trt_est p1_latch pvf m_trt_ref
if isempty(initialised)
    initialised = true;
    state    = C.init.state;
    mapping  = C.init.mapping;
    vane_cmd = C.init.vane;
    op       = C.init.op;
    e0       = median3(meas(1), meas(2), meas(3)) - C.sp;   % filter starts at the measurement
    I        = op - kp_of(mapping, C) * e0;
    track_t  = 0;  trip_t = 0;  loaded_t = 0;  cb_trp = 0;  p1_latch = 0;
    m_trt_est = C.init.m_trt;
    m_trt_ref = C.init.m_trt;
    pvf       = median3(meas(1), meas(2), meas(3));
end
Ts = C.Ts;

%% Inputs
pv  = median3(meas(1), meas(2), meas(3));       % PY-100V
pvf = pvf + Ts / (C.tau_f + Ts) * (pv - pvf);   % first-order PV filter (noise -> actuator wear)
e   = pvf - C.sp;                               % [bar], direct action
p1  = meas(4) * 1e5 + C.p_atm;                  % header [Pa a]
p2  = meas(5) * 1e5 + C.p_atm;                  % network [Pa a]
T   = meas(6) + 273.15;
zsc = meas(10) > 0.5;
jt  = meas(11);
m_bp_now = bp_flow(meas(8) / 100, p1, p2, T, C.P) + bp_flow(meas(9) / 100, p1, p2, T, C.P);

%% Trip initiation (first scan)
if scn(3) > 0.5 && state ~= ST_TRIP
    state   = ST_TRIP;
    trip_t  = 0;
    mapping = MAP_BYPASS;
    if C.ff_enable > 0.5
        % m_trt_est was computed in the previous scan, before any trip action
        req     = m_bp_now + C.kFF * m_trt_est;
        op      = min(100, req / C.m_des * 100 / 1.2);
        track_t = C.t_track;
    else
        op      = min(100, m_bp_now / C.m_des * 100 / 1.2);   % bumpless remap only
        track_t = 0;
    end
    I = op - kp_of(mapping, C) * e;
end

%% PIC-100
kp = kp_of(mapping, C);
[ti, tt] = ti_of(mapping, C);
tracking = track_t > 0;
if tracking
    track_t = track_t - Ts;
    v      = op;
    op_sat = op;
    I      = op - kp * e;              % output tracking: release is bumpless
else
    v      = kp * e + I;
    op_sat = min(max(v, 0), 100);
end

%% PY-100S / PY-101: mapping and vane command
if state == ST_RUNNING
    vane_req = min(op_sat, 50) * 2;
    bp_req   = max(op_sat - 50, 0) / 50 * 120;
    vane_cmd = vane_cmd + min(max(vane_req - vane_cmd, -C.vane_rate * Ts), C.vane_rate * Ts);
    if op_sat <= 50
        op_ach = vane_cmd / 2;         % vanes rate-limited: feed back what is achievable
    else
        op_ach = op_sat;
    end
elseif state == ST_LOADING
    if loaded_t <= 0                   % ramp held while the bypass-closed condition is confirmed
        vane_cmd = min(vane_cmd + C.load_rate * Ts, 100);
    end
    % flow-transfer feedforward: the bypass gives up what the turbine is estimated to take
    ff_load  = C.load_ff * (m_trt_est - m_trt_ref) / C.m_des * 100;
    bp_req   = max(op_sat * 1.2 - ff_load, 0);
    op_ach   = op_sat;
else  % ST_TRIP
    vane_cmd = 0;
    bp_req   = op_sat * 1.2;
    op_ach   = op_sat;
end

%% Top pressure HH override (P1) latch, evaluated before anti-windup so the PI tracks it
if pv > C.p_HH
    p1_latch = 1;
elseif pv < C.p_H
    p1_latch = 0;
end
if p1_latch > 0.5
    op_ach = 100;                      % external reset feedback: PI follows the override
end

%% Anti-windup (back-calculation), only when not tracking
if ~tracking
    I  = I + kp * Ts / ti * e + Ts / tt * (op_ach - v);
    op = op_sat;
end

%% Loading complete -> RUNNING (bumpless remap to SPLIT)
if state == ST_LOADING
    if bp_req <= C.load_bp_done
        loaded_t = loaded_t + Ts;
    else
        loaded_t = 0;
    end
    if loaded_t >= C.load_hold || vane_cmd >= 100
        state   = ST_RUNNING;
        mapping = MAP_SPLIT;
        op      = vane_cmd / 2;
        I       = op - kp_of(mapping, C) * e;
    end
end

%% PY-201: flow request -> position, top pressure HH override
W1  = bp_req / 100 * C.m_des / 2;
pos = bp_position(W1, p1, p2, T, C.P) * 100;
if p1_latch > 0.5
    pos = 100;
end

%% Trip timing and sequential breaker trip
fast = 0;
if state == ST_TRIP
    trip_t = trip_t + Ts;
    fast   = double(trip_t <= C.t_fast);
    if zsc && jt < 0
        cb_trp = 1;
    end
else
    m_trt_est = trt_flow(meas(7) / 100, 1, p1, p2, T, C.P);  % latched for the next scan
end

%% Outputs
energ = double(state ~= ST_TRIP);
cmd = [vane_cmd; pos; pos; energ; energ; 1 - p1_latch; 1 - p1_latch; cb_trp; fast];
dg  = [pvf; op_sat; state; double(tracking); mapping; vane_cmd; bp_req; m_trt_est];
end

function k = kp_of(mapping, C)
% PIC-100 gain: separate tuning for the bypass-only mapping (gain scheduling)
if mapping == 0
    k = C.Kp_bp;
else
    k = C.Kp;
end
end

function [ti, tt] = ti_of(mapping, C)
if mapping == 0
    ti = C.Ti_bp;  tt = C.Tt_bp;
else
    ti = C.Ti;     tt = C.Tt;
end
end

function m = median3(a, b, c)
m = max(min(a, b), min(max(a, b), c));
end
