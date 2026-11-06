function M = loop_margins(P, C)
%LOOP_MARGINS Gain and phase margins of the bypass-only loop with the PI in C (Control System Toolbox).
L  = bypass_loop_model(P, C);
G  = ss(L.A, L.B, [1 0] / 1e5, 0);                       % OP -> p1 [bar]
G  = -G;                                                 % direct-acting controller: use +K on the error p - SP
for k = 1:numel(L.lags)
    G = G * tf(1, [L.lags(k) 1]);
end
G.InputDelay = L.delay;
K  = C.Kp_bp * tf([C.Ti_bp 1], [C.Ti_bp 0]);
[gm, pm, ~, wc] = margin(K * G);
M = struct('GM_dB', 20 * log10(gm), 'PM_deg', pm, 'wc', wc, 'Kp', C.Kp_bp, 'Ti', C.Ti_bp, 'tau_f', C.tau_f);
end
