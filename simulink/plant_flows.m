function [m_trt, m_bp, P_turb, p_in] = plant_flows(xa, ph, P)
%PLANT_FLOWS Algebraic flows and turbine power from actuator positions and header pressure.
%#codegen
[m_trt, p_in] = trt_flow(xa(1), xa(4), ph, P.pout, P.T_in, P);
m_bp = [bp_flow(xa(2), ph, P.pout, P.T_in, P); bp_flow(xa(3), ph, P.pout, P.T_in, P)];
if m_trt > 0 && p_in > P.pout
    P_turb = P.eta_is * m_trt * P.cp * P.T_in * (1 - (P.pout / p_in)^P.kexp);
else
    P_turb = 0;
end
end
