function run_scenarios()
%RUN_SCENARIOS Rebuild the model, run scenarios 0-4, save plots and the KPI table.
%   Outputs in simulink/results/:  S*.png, trip_hero.png, trip_sensitivity.png, kpi_table.csv/.md,
%   checks.md (steady-state and bumpless-transfer checks)
here = fileparts(mfilename('fullpath'));
cd(here);
res = fullfile(here, 'results');
if ~exist(res, 'dir'), mkdir(res); end
build_models();
load_system('trt_model');
S  = plot_style();
P  = params();
C0 = controller_config(P);
names = {'S0_steady', 'S1a_step_up', 'S1b_step_down', 'S2_slip', 'S3a_trip_ff', 'S3b_trip_noff', 'S3c_trip_pi_tight', 'S3d_trip_pi_tight_f03', 'S4_loading', 'S4b_loading_noff'};
titles = containers.Map(names, {'Steady state at the design point', ...
    'Blast-flow step +10 %', 'Blast-flow step -10 %', 'Furnace slip: +30 % for 5 s', ...
    'TRT trip at full load, feedforward + tracking', 'TRT trip at full load, feedback only', ...
    'TRT trip, feedback only, tight PI', 'TRT trip, feedback only, tight PI, light PV filter', ...
    'Loading: flow transfer bypass -> TRT (vane ramp + transfer feedforward, simplified sequence)', ...
    'Loading without transfer feedforward (feedback only)'});

R = struct();  K = struct();  M = struct();  CS = struct();
for i = 1:numel(names)
    [SCN, T, X0, C, Pi, meta] = make_scenario(names{i}, P, C0);
    tic;  r = run_one(SCN, T, X0, C, Pi);
    fprintf('%-16s simulated in %.1f s\n', names{i}, toc);
    R.(names{i}) = r;  M.(names{i}) = meta;  CS.(names{i}) = C;
    K.(names{i}) = compute_kpis(r, meta.t_ev, Pi, C);
    if ~startsWith(names{i}, 'S3')
        plot_scenario(r, meta, titles(names{i}), fullfile(res, [names{i} '.png']), C, S);
    end
end
plot_trip_hero(R.S3a_trip_ff, R.S3b_trip_noff, R.S3d_trip_pi_tight_f03, M.S3a_trip_ff.t_ev, C0, S, fullfile(res, 'trip_hero.png'));

%% Feedback-only reference: tuning, stability margins, noise-driven valve travel
fb = {'S3b_trip_noff', 'S3c_trip_pi_tight', 'S3d_trip_pi_tight_f03'};
fblab = {'Nominal (SIMC, tau_c = 6 s, filter 1 s)', 'Tight (SIMC tau_c = theta, filter 1 s)', 'Tight (SIMC tau_c = theta, filter 0.3 s)'};
fbrows = {};
for i = 1:numel(fb)
    Ci = CS.(fb{i});  mg = loop_margins(P, Ci);  ri = R.(fb{i});  ki = K.(fb{i});
    late = ri.t >= M.(fb{i}).t_ev + 60;                       % settled, noise only
    trav = (sum(abs(diff(ri.thA(late)))) + sum(abs(diff(ri.thB(late))))) / (sum(late) * 0.05 / 60);
    fbrows{end + 1} = sprintf('| %s | %.0f | %.1f | %.1f | %.0f | %.3f | %.2f | %.0f |', fblab{i}, ...
        Ci.Kp_bp, Ci.Ti_bp, mg.GM_dB, mg.PM_deg, ki.max_dev_bar, ki.IAE_bar_s, trav); %#ok<AGROW>
end
% beyond SIMC: what feedback alone needs to reach the 90 mbar target
[SCN, T, X0, Cb] = make_scenario('S3d_trip_pi_tight_f03', P, C0);
for fac = [0.5 0.2]
    Lb = Cb.lin_bp;  tcb = fac * Lb.theta;  Ci = Cb;
    Ci.Kp_bp = Lb.tau1e / (Lb.K * (tcb + Lb.theta));  Ci.Ti_bp = min(Lb.tau1e, 4 * (tcb + Lb.theta));  Ci.Tt_bp = Ci.Ti_bp;
    mg = loop_margins(P, Ci);  ri = run_one(SCN, T, X0, Ci, P);  ki = compute_kpis(ri, 20, P, Ci);
    late = ri.t >= 80;
    trav = (sum(abs(diff(ri.thA(late)))) + sum(abs(diff(ri.thB(late))))) / (sum(late) * 0.05 / 60);
    fbrows{end + 1} = sprintf('| Beyond SIMC (tau_c = %.1f theta, filter 0.3 s) | %.0f | %.1f | %.1f | %.0f | %.3f | %.2f | %.0f |', ...
        fac, Ci.Kp_bp, Ci.Ti_bp, mg.GM_dB, mg.PM_deg, ki.max_dev_bar, ki.IAE_bar_s, trav); %#ok<AGROW>
end
mgF = loop_margins(P, CS.S3a_trip_ff);
fbrows{end + 1} = sprintf('| **Feedforward + tracking** (nominal PI) | %.0f | %.1f | %.1f | %.0f | **%.3f** | %.2f | – |', ...
    CS.S3a_trip_ff.Kp_bp, CS.S3a_trip_ff.Ti_bp, mgF.GM_dB, mgF.PM_deg, K.S3a_trip_ff.max_dev_bar, K.S3a_trip_ff.IAE_bar_s);

%% Checks: steady state and bumpless transfers
r0 = R.S0_steady;
chk = {};
chk{end+1} = sprintf('| Steady state: P_el | %.3f MW | design %.3f MW |', mean(r0.P_el), P.Pel_des / 1e6);
chk{end+1} = sprintf('| Steady state: top pressure | %.4f barg | SP %.2f barg |', mean(r0.p_top), C0.sp);
chk{end+1} = sprintf('| Steady state: vanes / bypass | %.2f %% / %.2f %% | design 80 %% / 0 %% |', mean(r0.alpha), mean(r0.thA));
r4 = R.S4_loading;  it = find(diff(r4.state) ~= 0, 1);
if ~isempty(it)
    w  = max(1, it - 4):min(numel(r4.t) - 1, it + 4);
    dZ = max(abs(diff(r4.cmd(w, 1))));  dB = max(abs(diff(r4.cmd(w, 2))));
    chk{end+1} = sprintf('| Loading -> RUNNING at t = %.1f s: largest command step (50 ms) | ZY-101 %.2f %%, PV-201A %.2f %% | bumpless if comparable to the ramp (0.025 %%/50 ms) and the bypass closing its last %.0f %% flow |', ...
        r4.t(it), dZ, dB, C0.load_bp_done);
end
r3 = R.S3a_trip_ff;  ir = find(diff(r3.track) < 0, 1);
if ~isempty(ir)
    w  = max(1, ir - 4):min(numel(r3.t) - 1, ir + 4);
    chk{end+1} = sprintf('| Trip: release of output tracking at t = %.1f s: largest PV-201A command step (50 ms) | %.2f %% | bumpless |', ...
        r3.t(ir), max(abs(diff(r3.cmd(w, 2)))));
end

%% Trip sensitivity: ESD closing time x bypass stroke time, FF on/off; FF gain sweep
tc = [0.5 0.7 1.0];  ts = [1.0 1.5 2.0];  kff = [0.8 0.9 1.0 1.1 1.2];
peak = zeros(numel(tc), numel(ts), 2);
for a = 1:numel(tc)
    for b = 1:numel(ts)
        for f = 1:2
            Pq = P;  Pq.esd.t_close = tc(a);  Pq.bpv.rate_fast = 1 / ts(b);
            [SCN, T, X0, C] = make_scenario('S3a_trip_ff', Pq, C0);
            C.ff_enable = 2 - f;     % f = 1: FF on, f = 2: FF off
            r = run_one(SCN, 60, X0, C, Pq);
            peak(a, b, f) = max(r.p_top) - C.sp;
        end
    end
end
pk_k = zeros(size(kff));  iae_k = pk_k;
for j = 1:numel(kff)
    [SCN, T, X0, C] = make_scenario('S3a_trip_ff', P, C0);
    C.kFF = kff(j);
    r = run_one(SCN, 150, X0, C, P);
    kk = compute_kpis(r, 20, P, C);
    pk_k(j) = kk.max_dev_bar;  iae_k(j) = kk.IAE_bar_s;
end
plot_sensitivity(tc, ts, peak, kff, pk_k, iae_k, C0, S, fullfile(res, 'trip_sensitivity.png'));

%% KPI table
rows = names(2:end);
lab  = {'S1a step +10 %', 'S1b step -10 %', 'S2 slip +30 %/5 s', 'S3a trip, FF + tracking', 'S3b trip, feedback only', ...
        'S3c trip, feedback only, tight PI', 'S3d trip, feedback only, tight PI + light filter', 'S4 loading, transfer FF', 'S4b loading, feedback only'};
f = {'max_dev_bar', 'max_dev_pct', 'IAE_bar_s', 'std_mbar', 't_rec_s', 'bypass_Nm3', 'E_lost_MWh', 'P_el_mean_MW', 'vane_travel_pct', 'bp_travel_pct'};
hdr = {'Max dev [bar]', 'Max dev [% SP]', 'IAE [bar s]', 'Std [mbar]', 'Recovery +/-10 mbar [s]', 'Bypass gas [Nm3]', 'Energy lost [MWh]', 'Mean P_el [MW]', 'Vane travel [%]', 'Bypass travel [%]'};
tab = zeros(numel(rows), numel(f));
for i = 1:numel(rows)
    for j = 1:numel(f), tab(i, j) = K.(rows{i}).(f{j}); end
end
Tt = array2table(tab, 'VariableNames', f, 'RowNames', lab);
writetable(Tt, fullfile(res, 'kpi_table.csv'), 'WriteRowNames', true);
fid = fopen(fullfile(res, 'kpi_table.md'), 'w');
fprintf(fid, '# KPI table (phase 3)\n\nGenerated by `run_scenarios.m`. Top-pressure deviation from the true (noise-free) pressure; disturbance at t = 20 s (S4: 10 s). Set point 1.8 barg, target for the trip < 0.09 bar (5 %% of SP).\n\n');
fprintf(fid, '| Scenario | %s |\n|---|%s\n', strjoin(hdr, ' | '), repmat('---|', 1, numel(hdr)));
fmt = {'%.3f', '%.1f', '%.2f', '%.1f', '%.0f', '%.0f', '%.3f', '%.2f', '%.0f', '%.0f'};
for i = 1:numel(rows)
    c = arrayfun(@(j) sprintf(fmt{j}, tab(i, j)), 1:numel(f), 'UniformOutput', false);
    fprintf(fid, '| %s | %s |\n', lab{i}, strjoin(c, ' | '));
end
fprintf(fid, '\n## Trip: how far can feedback alone go?\n\nBypass-only loop (after the trip). Margins on the linearised loop (positioner, transmitter, PV filter, sampling and one-scan delay). Valve travel = noise-driven movement of PV-201A+B once settled.\n\n');
fprintf(fid, '| Tuning | Kp [%%/bar] | Ti [s] | GM [dB] | PM [deg] | Peak dev [bar] | IAE [bar s] | Valve travel [%%/min] |\n|---|---|---|---|---|---|---|---|\n%s\n', strjoin(fbrows, newline));
fprintf(fid, '\n## Trip sensitivity: peak top-pressure rise [bar]\n\n| ESD closing time | ');
fprintf(fid, '%s', strjoin(arrayfun(@(b) sprintf('FF, bypass %.1f s', b), ts, 'UniformOutput', false), ' | '));
fprintf(fid, ' | %s |\n|---|%s\n', strjoin(arrayfun(@(b) sprintf('no FF, bypass %.1f s', b), ts, 'UniformOutput', false), ' | '), repmat('---|', 1, 2 * numel(ts)));
for a = 1:numel(tc)
    fprintf(fid, '| %.1f s | %s | %s |\n', tc(a), strjoin(arrayfun(@(v) sprintf('%.3f', v), peak(a, :, 1), 'UniformOutput', false), ' | '), ...
        strjoin(arrayfun(@(v) sprintf('%.3f', v), peak(a, :, 2), 'UniformOutput', false), ' | '));
end
fprintf(fid, '\n## Feedforward gain sweep (ESD 0.7 s, bypass 1.5 s)\n\n| k_FF | %s |\n|---|%s\n| Peak dev [bar] | %s |\n| IAE [bar s] | %s |\n', ...
    strjoin(arrayfun(@(v) sprintf('%.1f', v), kff, 'UniformOutput', false), ' | '), repmat('---|', 1, numel(kff)), ...
    strjoin(arrayfun(@(v) sprintf('%.3f', v), pk_k, 'UniformOutput', false), ' | '), ...
    strjoin(arrayfun(@(v) sprintf('%.2f', v), iae_k, 'UniformOutput', false), ' | '));
fprintf(fid, '\n## Checks\n\n| Check | Result | Reference |\n|---|---|---|\n%s\n', strjoin(chk, newline));
fprintf(fid, '\n## Controller tuning (SIMC, see controller_config.m)\n\n| Parameter | Value |\n|---|---|\n');
fprintf(fid, '| Plant: dominant / second time constant | %.1f s / %.1f s |\n| Plant: gain OP -> top pressure | %.4f bar/%% |\n', C0.lin.tau1, C0.lin.tau2, C0.lin.K);
fprintf(fid, '| PV filter | %.1f s |\n| Effective lag / dead time (SIMC half rule) | %.1f s / %.2f s |\n| Desired closed-loop tau_c | %.1f s |\n', C0.tau_f, C0.lin.tau1e, C0.lin.theta, C0.tau_c);
fprintf(fid, '| PIC-100 Kp (SPLIT) | %.0f %%/bar |\n| PIC-100 Kp (BYPASS_ONLY) | %.0f %%/bar |\n| PIC-100 Ti | %.1f s |\n', C0.Kp, C0.Kp * C0.kp_bp_factor, C0.Ti);
fclose(fid);
save(fullfile(res, 'results.mat'), 'K', 'peak', 'tc', 'ts', 'kff', 'pk_k', 'iae_k');
fprintf('Results written to %s\n', res);
type(fullfile(res, 'kpi_table.md'));
end

%% ======================================================================
function plot_scenario(r, meta, ttl, file, C, S)
fig = figure('Visible', 'off', 'Position', [100 100 1000 640]);  light_theme(fig);
tl = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tl, ttl, 'FontWeight', 'bold', 'FontSize', 12, 'Color', S.navy);
t = r.t;
ax1 = nexttile;  hold on;
fill([t(1) t(end) t(end) t(1)], C.sp + 0.09 * [-1 -1 1 1], S.band, 'EdgeColor', 'none');
plot(t, r.pv, 'Color', [S.gray 0.6], 'LineWidth', 0.8);
plot(t, r.p_top, 'Color', S.navy);
yline(C.sp, '--', 'Color', S.gray);
ylabel('Top pressure [barg]');  legend({'±5 % band', 'measured (voted)', 'true', 'set point'}, 'Location', 'eastoutside');
ax2 = nexttile;  hold on;
plot(t, r.alpha, 'Color', S.navy);  plot(t, r.thA, 'Color', S.orange);  plot(t, r.x_esd, ':', 'Color', S.gray);
ylabel('Position [%]');  legend({'stator vanes', 'bypass PV-201A/B', 'ESD XV-101'}, 'Location', 'eastoutside');  ylim([-5 105]);
ax3 = nexttile;  hold on;
plot(t, r.m_in, 'Color', S.gray);  plot(t, r.m_trt, 'Color', S.navy);  plot(t, r.m_bp, 'Color', S.orange);
ylabel('Mass flow [kg/s]');
yyaxis right;  plot(t, r.P_el, '-', 'Color', S.blue, 'LineWidth', 1.0);  ylabel('P_{el} [MW]');
ax3.YAxis(2).Color = S.blue;
legend({'from furnace', 'turbine', 'bypass', 'P_{el}'}, 'Location', 'eastoutside');
xlabel('Time [s]');  linkaxes([ax1 ax2 ax3], 'x');  xlim([t(1) t(end)]);
exportgraphics(fig, file, 'Resolution', 200);  close(fig);
end

function plot_sensitivity(tc, ts, peak, kff, pk, iae, C, S, file)
fig = figure('Visible', 'off', 'Position', [100 100 1100 400]);  light_theme(fig);
tl = tiledlayout(fig, 1, 2, 'TileSpacing', 'loose', 'Padding', 'compact');
title(tl, 'Trip sensitivity: actuator speeds and feedforward gain', 'FontWeight', 'bold', 'Color', S.navy);
nexttile;  hold on;
cols = {S.blue, S.orange, S.navy};
h = gobjects(0);  lg = {};
for b = 1:numel(ts)
    h(end + 1) = plot(tc, 1e3 * peak(:, b, 1), '-o', 'Color', cols{b}, 'MarkerFaceColor', cols{b}); %#ok<AGROW>
    lg{end + 1} = sprintf('FF, bypass stroke %.1f s', ts(b)); %#ok<AGROW>
end
h(end + 1) = plot(tc, 1e3 * max(peak(:, :, 2), [], 2), '--s', 'Color', S.gray, 'MarkerFaceColor', S.gray);
lg{end + 1} = 'feedback only (all stroke times)';
yline(90, ':', 'target 90 mbar', 'Color', S.gray, 'LabelHorizontalAlignment', 'left');
xlabel('ESD closing time [s]');  ylabel('Peak top-pressure rise [mbar]');  ylim([0 250]);
legend(h, lg, 'Location', 'east', 'FontSize', 8);
ax = nexttile;  hold on;
yyaxis left;   plot(kff, 1e3 * pk, '-o', 'Color', S.orange, 'MarkerFaceColor', S.orange);  ylabel('Peak rise [mbar]');
yyaxis right;  plot(kff, iae, '-s', 'Color', S.navy);  ylabel('IAE [bar s]');
ax.YAxis(1).Color = S.orange;  ax.YAxis(2).Color = S.navy;
xlabel('Feedforward gain k_{FF}');  legend({'peak rise', 'IAE'}, 'Location', 'north');
exportgraphics(fig, file, 'Resolution', 200);  close(fig);
end

function light_theme(fig)
% R2025a follows the desktop theme; result plots are always exported in the light theme
try
    fig.Theme = 'light';
catch
end
end
