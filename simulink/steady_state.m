function [X0, C] = steady_state(P, C, kind, m_in, alpha0)
%STEADY_STATE Initial plant states and controller initialisation for a scenario.
%   [X0, C] = steady_state(P, C, 'running', m_in)          vanes control, bypass closed
%   [X0, C] = steady_state(P, C, 'loading', m_in, alpha0)  vanes fixed at alpha0, bypass takes the rest
%   Top pressure at set point in both cases. C.init is updated so the PLC starts bumpless.

p_top = C.sp * 1e5 + P.p_atm;
ph    = p_top - P.k_clean * m_in^2;
T     = P.T_in;
switch lower(kind)
    case 'running'
        alpha = fzero(@(a) trt_flow(a, 1, ph, P.pout, T, P) - m_in, [0.05 1]);
        th    = 0;
        C.init.state = 6;  C.init.mapping = 1;
        C.init.op    = alpha * 100 / 2;
    case 'loading'
        alpha = alpha0;
        m_bp  = m_in - trt_flow(alpha, 1, ph, P.pout, T, P);
        th    = bp_position(m_bp / 2, ph, P.pout, T, P);
        C.init.state = 5;  C.init.mapping = 0;
        C.init.op    = (m_bp / C.m_des * 100) / 1.2;
    otherwise
        error('Unknown steady state "%s"', kind);
end
X0.xa  = [alpha; th; th; 1];
X0.ph  = ph;
X0.p1  = p_top;
X0.w   = P.w_nom;
X0.xpt = p_top * [1; 1; 1];
C.init.vane  = alpha * 100;
C.init.m_trt = trt_flow(alpha, 1, ph, P.pout, T, P);
C.init.cmd   = [alpha * 100; th * 100; th * 100; 1; 1; 1; 1; 0; 0];
end
