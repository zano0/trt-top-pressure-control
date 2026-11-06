function plot_trip_hero(rf, rn, rt, t_ev, C, S, file)
%PLOT_TRIP_HERO Key-result figure: full-load trip, feedforward vs feedback only.
%   Drawn at the size it is printed in the portfolio PDF (19 x 12.5 cm), so the font sizes
%   below are the printed sizes (axes and labels 11 pt). Two panels: top pressure and mass flows.
fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2 2 19 12.5]);
try, fig.Theme = 'light'; catch, end
fs = 11;
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
tf = rf.t - t_ev;  tn = rn.t - t_ev;  tt = rt.t - t_ev;  xl = [-5 60];

ax1 = nexttile(tl);  hold(ax1, 'on');
fill(ax1, [xl(1) xl(2) xl(2) xl(1)], C.sp + 0.09 * [-1 -1 1 1], S.band, 'EdgeColor', 'none');
yline(ax1, C.sp, '--', 'Color', S.gray, 'LineWidth', 1);
yline(ax1, C.p_HH, ':', 'HH', 'Color', S.navy, 'LineWidth', 1.2, 'FontSize', fs, ...
    'LabelHorizontalAlignment', 'left', 'LabelVerticalAlignment', 'bottom');
plot(ax1, tn, rn.p_top, 'Color', S.gray, 'LineWidth', 2);
plot(ax1, tt, rt.p_top, '--', 'Color', S.blue, 'LineWidth', 2);
plot(ax1, tf, rf.p_top, 'Color', S.orange, 'LineWidth', 2.6);
[pn, i2] = max(rn.p_top);  [pt_, i3] = max(rt.p_top);  [pf, i1] = max(rf.p_top);
text(ax1, tn(i2) + 3, pn + 0.008, sprintf('nominal PI  +%.0f mbar', 1e3 * (pn - C.sp)), ...
    'Color', S.gray, 'FontWeight', 'bold', 'FontSize', fs);
text(ax1, 37, C.sp + 0.045, sprintf('tight PI  +%.0f mbar', 1e3 * (pt_ - C.sp)), ...
    'Color', S.blue, 'FontWeight', 'bold', 'FontSize', fs);
text(ax1, tf(i1) + 3, pf + 0.018, sprintf('feedforward  +%.0f mbar', 1e3 * (pf - C.sp)), ...
    'Color', S.orange, 'FontWeight', 'bold', 'FontSize', fs);
text(ax1, xl(2) - 1, C.sp - 0.035, '±5 % band', 'Color', S.gray, 'FontSize', fs, 'HorizontalAlignment', 'right');
ylabel(ax1, 'Top pressure [barg]');  ylim(ax1, [C.sp - 0.05, max(pn, C.sp + 0.09) + 0.04]);
set(ax1, 'FontSize', fs, 'XTickLabel', []);  xlim(ax1, xl);

ax2 = nexttile(tl);  hold(ax2, 'on');
h = gobjects(5, 1);
h(5) = yline(ax2, rf.m_in(1), ':', 'Color', S.navy, 'LineWidth', 1.2);
h(1) = plot(ax2, tf, rf.m_trt, 'Color', S.navy, 'LineWidth', 2);
h(2) = plot(ax2, tf, rf.m_bp, 'Color', S.orange, 'LineWidth', 2.6);
h(3) = plot(ax2, tt, rt.m_bp, '--', 'Color', S.blue, 'LineWidth', 2);
h(4) = plot(ax2, tn, rn.m_bp, 'Color', S.gray, 'LineWidth', 2);
uistack(h(2), 'top');
legend(ax2, h, {'turbine', 'bypass, feedforward', 'bypass, tight PI', 'bypass, nominal PI', 'gas from furnace'}, ...
    'Location', 'southeast', 'FontSize', fs, 'Box', 'off');
ylabel(ax2, 'Mass flow [kg/s]');  xlabel(ax2, 'Time after trip [s]');
set(ax2, 'FontSize', fs);  xlim(ax2, xl);  ylim(ax2, [0 145]);
exportgraphics(fig, file, 'Resolution', 250);  close(fig);
end
