function R = read_log(out, P)
%READ_LOG Decode the LOG signal of trt_model into named fields (engineering units).
%   Column layout = [plant log (16); cmd (9); dg (8); meas (13)] (see build_models.m)
V = out.LOG.signals.values;
if ndims(V) == 3, V = squeeze(V)'; end
R.t      = out.LOG.time(:);
R.p_top  = (V(:, 1) - P.p_atm) / 1e5;   % [barg] true top pressure
R.p_h    = (V(:, 2) - P.p_atm) / 1e5;   % [barg]
R.m_in   = V(:, 3);                     % [kg/s]
R.m_trt  = V(:, 4);
R.m_bpA  = V(:, 5);
R.m_bpB  = V(:, 6);
R.m_bp   = V(:, 5) + V(:, 6);
R.P_turb = V(:, 7) / 1e6;               % [MW]
R.P_el   = V(:, 8) / 1e6;               % [MW]
R.n      = V(:, 9) * 60 / (2 * pi);     % [rpm]
R.alpha  = V(:, 10) * 100;              % [%]
R.thA    = V(:, 11) * 100;
R.thB    = V(:, 12) * 100;
R.x_esd  = V(:, 13) * 100;
R.p_in   = (V(:, 14) - P.p_atm) / 1e5;
R.cb     = V(:, 15);
R.m_c    = V(:, 16);                    % [kg/s] flow through gas cleaning
R.cmd    = V(:, 17:25);
R.pv     = V(:, 26);                    % voted top pressure [barg]
R.op     = V(:, 27);                    % PIC-100 OP [%]
R.state  = V(:, 28);
R.track  = V(:, 29);
R.map    = V(:, 30);
R.vane_cmd = V(:, 31);
R.bp_req = V(:, 32);
R.m_trt_est = V(:, 33);
R.meas   = V(:, 34:46);
end
