function [m, p_in] = trt_flow(alpha, x_esd, p_h, p_out, T, P)
%TRT_FLOW Gas flow through ESD XV-101 + turbine T-101 (Stodola ellipse law).
%   [m, p_in] = trt_flow(alpha, x_esd, p_h, p_out, T, P)
%   alpha  stator-vane opening 0..1     x_esd  ESD opening 0..1
%   p_h    header pressure [Pa a]        p_out  network pressure [Pa a]
%   m      mass flow [kg/s]              p_in   turbine inlet pressure [Pa a]
%
%   Turbine:  m^2 = a (p_in^2 - p_out^2),     a = (K alpha)^2 / T
%   ESD:      p_h - p_in = b m^2,             b = k_esd / phi^2,  phi = x_esd^n
%   With y = m^2:  a b^2 y^2 - (2 a b p_h + 1) y + a (p_h^2 - p_out^2) = 0
%   Smaller root in the cancellation-free form y = 2c / (B + sqrt(B^2 - 4 A c)).
%#codegen
alpha = min(max(alpha, 0), 1);
phi   = min(max(x_esd, 0), 1)^P.esd.phi_exp;
a     = (P.K_stod * alpha)^2 / T;
c     = a * max(p_h^2 - p_out^2, 0);
if a <= 0 || phi < 1e-6 || c <= 0
    m = 0;  p_in = p_out;  return
end
b  = P.k_esd / phi^2;
A  = a * b^2;
B  = 2 * a * b * p_h + 1;
y  = 2 * c / (B + sqrt(max(B^2 - 4 * A * c, 0)));
m  = sqrt(y);
p_in = p_h - b * y;
end
