function W = bp_flow(theta, p1, p2, T, P)
%BP_FLOW Mass flow through one bypass valve PV-201A/B, ISA-75.01 / IEC 60534-2-1 (gas).
%   W = bp_flow(theta, p1, p2, T, P)
%   theta  valve travel 0..1          p1, p2  upstream / downstream pressure [Pa a]
%   T      gas temperature [K]        W       mass flow [kg/s]
%   Equal-percentage inherent characteristic, zero at closed. Choked flow limit x <= Fk*xT.
%#codegen
theta = min(max(theta, 0), 1);
f     = (P.bp.R^theta - 1) / (P.bp.R - 1);
x_ch  = P.bp.Fk * P.bp.xT;
x     = max(p1 - p2, 0) / max(p1, 1);
x     = min(x, x_ch);
Y     = 1 - x / (3 * x_ch);
rho1  = p1 / (P.R_s * T);
W     = P.bp.N6 * P.bp.Fp * P.bp.Kv * f * Y * sqrt(x * (p1 / 1e5) * rho1) / 3600;
end
