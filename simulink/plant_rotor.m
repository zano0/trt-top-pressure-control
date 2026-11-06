function [wdot, P_el, cb] = plant_rotor(P_turb, w, cmd, scn, P)
%PLANT_ROTOR Rotor and generator, two modes switched by the breaker CB-101.
%   CB-101 closed: w fixed by the grid (infinite bus), P_el = (P_turb - P_loss) * eta_gen
%   CB-101 open  : J w dw/dt = P_turb - P_loss, P_el = 0
%   CB-101 is closed when the grid is available and no trip command has been issued.
%#codegen
P_loss = P.c_loss * w^2;
cb = double(scn(4) > 0.5 && cmd(8) < 0.5);
if cb > 0.5
    wdot = 0;
    P_el = (P_turb - P_loss) * P.eta_gen;
else
    wdot = (P_turb - P_loss) / (P.J * max(w, 1));
    P_el = 0;
end
end
