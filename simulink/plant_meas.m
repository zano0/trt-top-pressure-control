function meas = plant_meas(xpt, scn, ph, xa, P_el, cb, w, P)
%PLANT_MEAS Field measurements in engineering units, as read by the PLC (see trt_controller_step).
%#codegen
meas = zeros(13, 1);
meas(1:3) = (xpt - P.p_atm) / 1e5 + scn(5:7) + scn(8:10);   % PT-100A/B/C + noise + fault
meas(4)   = (ph - P.p_atm) / 1e5;                           % PT-110
meas(5)   = (P.pout - P.p_atm) / 1e5;                       % PT-300
meas(6)   = P.T_in - 273.15;                                % TT-101
meas(7:9) = xa(1:3) * 100;                                  % ZT-101, ZT-201A/B
meas(10)  = double(xa(4) < P.esd.x_closed);                 % ZSC-101
meas(11)  = P_el / 1e6;                                     % JT-101
meas(12)  = cb;                                             % CB-101-ST
meas(13)  = w * 60 / (2 * pi);                              % ST-101
end
