function L = bypass_loop_model(P, C)
%BYPASS_LOOP_MODEL Linear model of the top-pressure loop acting on the bypass (TRT tripped).
%   Input: PIC-100 OP [%] in BYPASS_ONLY mapping (1.2 % design flow per % OP).
%   States p1 (V1), p2 (V2). Self-regulation of the header from the choked bypass: dm/dp = m/p.
gc = P.mdot_des / (2 * P.dp_clean_des);
gb = P.mdot_des / P.ph_des;                              % choked valve: flow proportional to p1
b  = 1.2 / 100 * P.mdot_des;                             % [kg/s per % OP]
A  = [-gc / P.C1, gc / P.C1; gc / P.C2, -(gc + gb) / P.C2];
B  = [0; -b / P.C2];
lam = sort(eig(A));
L.A = A;  L.B = B;
L.K    = abs([1 0] * (A \ B)) / 1e5;                     % [bar per % OP]
L.tau1 = -1 / lam(2);  L.tau2 = -1 / lam(1);
L.lags  = [P.bpv.tau, P.pt.tau, C.tau_f];                % positioner, transmitter, PV filter
L.delay = P.Ts / 2 + P.Ts;                               % sampling + one-scan output update
L.tau1e = L.tau1 + L.tau2 / 2;
L.theta = sum(L.lags) + L.delay + L.tau2 / 2;
end
