function theta = bp_position(W, p1, p2, T, P)
%BP_POSITION Inverse of BP_FLOW: travel 0..1 that passes mass flow W [kg/s] in one valve.
%   Used by PY-201 (flow request -> position) and by the trip feedforward.
%#codegen
x_ch  = P.bp.Fk * P.bp.xT;
x     = max(p1 - p2, 0) / max(p1, 1);
x     = min(max(x, 1e-4), x_ch);
Y     = 1 - x / (3 * x_ch);
rho1  = p1 / (P.R_s * T);
Wmax  = P.bp.N6 * P.bp.Fp * P.bp.Kv * Y * sqrt(x * (p1 / 1e5) * rho1) / 3600;  % flow at f = 1
f     = min(max(W / Wmax, 0), 1);
theta = log(1 + f * (P.bp.R - 1)) / log(P.bp.R);
end
