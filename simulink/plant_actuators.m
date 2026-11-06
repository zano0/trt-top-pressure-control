function xadot = plant_actuators(cmd, xa, P)
%PLANT_ACTUATORS Rate-limited first-order actuators: vanes, PV-201A/B, ESD XV-101.
%   xa = [alpha; thetaA; thetaB; x_esd] (0..1), cmd = PLC output vector (see trt_controller_step)
%   dx/dt = sat((u - x)/tau, -rate, +rate). The integrator limits x to [0, 1].
%#codegen
xadot = zeros(4, 1);
% stator vanes: XY-102 de-energised -> hydraulics dumped, quick close
if cmd(5) > 0.5
    u = cmd(1) / 100;  r = P.vane.rate;
else
    u = 0;             r = P.vane.rate_trip;
end
xadot(1) = min(max((u - xa(1)) / P.vane.tau, -r), r);
% bypass valves: XY-201 de-energised -> fully open; fast stroke after a trip
for k = 1:2
    if cmd(5 + k) > 0.5
        u = cmd(1 + k) / 100;
    else
        u = 1;
    end
    if cmd(9) > 0.5 || cmd(5 + k) < 0.5
        r = P.bpv.rate_fast;
    else
        r = P.bpv.rate;
    end
    xadot(1 + k) = min(max((u - xa(1 + k)) / P.bpv.tau, -r), r);
end
% ESD XV-101: energised -> opens slowly, de-energised -> closes in t_close
if cmd(4) > 0.5
    xadot(4) = 1 / P.esd.t_open;
else
    xadot(4) = -1 / P.esd.t_close;
end
end
