function S = plot_style()
%PLOT_STYLE Common colours and figure defaults for all result plots.
S.navy   = [31 42 68] / 255;
S.blue   = [61 108 185] / 255;
S.orange = [217 130 43] / 255;
S.gray   = [138 148 166] / 255;
S.band   = [0.93 0.94 0.96];
S.font   = 'Helvetica';
set(groot, 'defaultAxesFontName', S.font, 'defaultTextFontName', S.font, ...
    'defaultAxesFontSize', 10, 'defaultLineLineWidth', 1.6, 'defaultAxesBox', 'off', ...
    'defaultAxesXGrid', 'on', 'defaultAxesYGrid', 'on', 'defaultAxesGridAlpha', 0.15, ...
    'defaultAxesTickDir', 'out', 'defaultFigureColor', 'w');
end
