function plot_tournament(dataFile, outputDir)
%PLOT_TOURNAMENT  Generate all tournament analysis plots from saved results.
%
%   plot_tournament()
%   plot_tournament('outputs/tournament_all_results.csv')
%   plot_tournament('outputs/tournament_all_results.csv', 'outputs')

if nargin < 1 || isempty(dataFile)
    dataFile = fullfile('outputs', 'tournament_all_results.csv');
end
if nargin < 2 || isempty(outputDir)
    outputDir = 'outputs';
end

if ~exist(dataFile, 'file')
    error('Data file not found: %s\nRun tournament() first.', dataFile);
end
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

T = readtable(dataFile, 'TextType', 'string');

agents = {'random','heuristic','monte_carlo','mcts'};
nA = numel(agents);

T2 = T(T.player_count == 2, :);
T4 = T(T.player_count == 4, :);

timestamp = char(datetime('now','Format','yyyyMMdd_HHmmss'));

plot1_pairwise_heatmap(T2, agents, nA, outputDir, timestamp);
plot2_4p_winrate(T4, agents, nA, outputDir, timestamp);
plot3_vp_boxplot(T2, T4, agents, nA, outputDir, timestamp);
plot4_game_length(T2, T4, outputDir, timestamp);

fprintf('\n=== DATA SUMMARY ===\n');
print_summary(T2, T4, agents, nA);

fprintf('\nAll plots saved to: %s/\n', outputDir);
end

%% =========================================================================
%  PLOT 1 — Pairwise heatmap
%% =========================================================================

function plot1_pairwise_heatmap(T2, agents, nA, outDir, ts)
winMat = NaN(nA, nA);

for i = 1:nA
    for j = 1:nA
        if i == j, continue; end
        ai = agents{i};
        aj = agents{j};

        wins = 0; seats = 0;
        for r = 1:height(T2)
            p1 = char(T2.p1_agent(r));
            p2 = char(T2.p2_agent(r));
            w  = char(T2.winner_agent(r));

            if strcmp(p1, ai) && strcmp(p2, aj)
                seats = seats + 1;
                if strcmp(w, ai), wins = wins + 1; end
            elseif strcmp(p2, ai) && strcmp(p1, aj)
                seats = seats + 1;
                if strcmp(w, ai), wins = wins + 1; end
            end
        end

        if seats > 0
            winMat(i,j) = wins / seats;
        end
    end
end

fig = figure('Visible','off','Position',[100 100 620 500]);
ax = axes(fig);

% Draw colored cells manually so NaN cells are clearly gray
hold(ax, 'on');
cmap = parula(256);

for i = 1:nA
    for j = 1:nA
        if isnan(winMat(i,j))
            fill(ax, [j-0.5 j+0.5 j+0.5 j-0.5], [i-0.5 i-0.5 i+0.5 i+0.5], ...
                [0.82 0.82 0.82], 'EdgeColor','w', 'LineWidth', 0.5);
            text(ax, j, i, '—', 'HorizontalAlignment','center', ...
                'VerticalAlignment','middle', 'Color',[0.45 0.45 0.45], 'FontSize', 12);
        else
            cidx = max(1, min(256, round(winMat(i,j) * 255) + 1));
            fill(ax, [j-0.5 j+0.5 j+0.5 j-0.5], [i-0.5 i-0.5 i+0.5 i+0.5], ...
                cmap(cidx,:), 'EdgeColor','w', 'LineWidth', 0.5);
            if winMat(i,j) < 0.35 || winMat(i,j) > 0.70
                txtclr = 'w';
            else
                txtclr = 'k';
            end
            text(ax, j, i, sprintf('%.2f', winMat(i,j)), ...
                'HorizontalAlignment','center', 'VerticalAlignment','middle', ...
                'Color', txtclr, 'FontSize', 12, 'FontWeight', 'bold');
        end
    end
end

colormap(ax, cmap);
cb = colorbar(ax);
cb.Label.String = 'Win Rate';
clim(ax, [0 1]);

set(ax, 'XTick', 1:nA, 'XTickLabel', agents, 'XTickLabelRotation', 25, ...
        'YTick', 1:nA, 'YTickLabel', agents, ...
        'TickLabelInterpreter', 'none', ...
        'XLim', [0.5 nA+0.5], 'YLim', [0.5 nA+0.5], ...
        'YDir', 'normal', 'FontSize', 11);

xlabel(ax, 'Opponent', 'FontSize', 13);
ylabel(ax, 'Agent', 'FontSize', 13);
title(ax, '1v1 Pairwise Win Rate (row agent vs column agent)', 'FontSize', 13);
box(ax, 'on');

saveas(fig, fullfile(outDir, [ts '_plot1_pairwise_heatmap.png']));
close(fig);
fprintf('Plot 1 saved.\n');
end

%% =========================================================================
%  PLOT 2 — 4-player win rate (no CI)
%% =========================================================================

function plot2_4p_winrate(T4, agents, nA, outDir, ts)
if isempty(T4)
    fprintf('Plot 2: no 4-player data, skipping.\n');
    return;
end

wins  = zeros(1, nA);
total = height(T4);

for r = 1:total
    w = char(T4.winner_agent(r));
    for i = 1:nA
        if strcmp(w, agents{i})
            wins(i) = wins(i) + 1;
            break;
        end
    end
end

wr = wins / total;

fig = figure('Visible','off','Position',[100 100 560 460]);
ax = axes(fig);

b = bar(ax, 1:nA, wr, 0.55, 'FaceColor','flat');
for i = 1:nA
    b.CData(i,:) = agentColor(i);
end

hold(ax, 'on');


for i = 1:nA
    text(ax, i, wr(i) + 0.012, sprintf('%.1f%%', wr(i)*100), ...
        'HorizontalAlignment', 'center', 'FontSize', 11, 'FontWeight', 'bold');
end

set(ax, 'XTick', 1:nA, 'XTickLabel', agents, ...
        'TickLabelInterpreter', 'none', 'FontSize', 11);
ylabel(ax, 'Win Rate', 'FontSize', 13);
ylim(ax, [0 max(wr)*1.35 + 0.05]);
title(ax, sprintf('4-Player Win Rate  (n=%d games)', total), 'FontSize', 13);
grid(ax, 'on');
ax.GridAlpha = 0.25;
box(ax, 'off');

saveas(fig, fullfile(outDir, [ts '_plot2_4p_winrate.png']));
close(fig);
fprintf('Plot 2 saved.\n');
end

%% =========================================================================
%  PLOT 3 — VP boxplots
%% =========================================================================

function plot3_vp_boxplot(T2, T4, agents, nA, outDir, ts)
fig = figure('Visible','off','Position',[100 100 1000 460]);

% --- 1v1 ---
ax1 = subplot(1, 2, 1);
means2 = zeros(1, nA);
for i = 1:nA
    vp = [];
    for p = 1:2
        agentCol = sprintf('p%d_agent', p);
        vpCol    = sprintf('p%d_vp',    p);
        if ~ismember(agentCol, T2.Properties.VariableNames), continue; end
        mask = agentMatch(T2.(agentCol), agents{i});
        vals = T2.(vpCol)(mask);
        if isnumeric(vals)
            vp = [vp; vals(~isnan(vals))]; %#ok<AGROW>
        end
    end
    if ~isempty(vp), means2(i) = mean(vp); end
end
draw_bar(ax1, means2, agents, nA, '1v1 Mean Final VP');

% --- 4-player ---
ax2 = subplot(1, 2, 2);
means4 = zeros(1, nA);
for i = 1:nA
    vp = [];
    for p = 1:4
        agentCol = sprintf('p%d_agent', p);
        vpCol    = sprintf('p%d_vp',    p);
        if ~ismember(agentCol, T4.Properties.VariableNames), continue; end
        mask = agentMatch(T4.(agentCol), agents{i});
        vals = T4.(vpCol)(mask);
        if isnumeric(vals)
            vp = [vp; vals(~isnan(vals))]; %#ok<AGROW>
        end
    end
    if ~isempty(vp), means4(i) = mean(vp); end
end
draw_bar(ax2, means4, agents, nA, '4-Player Mean Final VP');

saveas(fig, fullfile(outDir, [ts '_plot3_vp_bars.png']));
close(fig);
fprintf('Plot 3 saved.\n');
end

function draw_bar(ax, means, agents, nA, titleStr)
b = bar(ax, 1:nA, means, 0.55, 'FaceColor', 'flat');
for i = 1:nA
    b.CData(i,:) = agentColor(i);
end
for i = 1:nA
    if means(i) > 0
        text(ax, i, means(i) + 0.1, sprintf('%.1f', means(i)), ...
            'HorizontalAlignment', 'center', ...
            'FontSize', 11, 'FontWeight', 'bold');
    end
end
set(ax, 'XTick', 1:nA, 'XTickLabel', agents, ...
        'TickLabelInterpreter', 'none', 'FontSize', 11);
ylabel(ax, 'Mean Final VP', 'FontSize', 12);
title(ax, titleStr, 'FontSize', 12);
ylim(ax, [0 max(means) * 1.2 + 1]);
grid(ax, 'on');
ax.GridAlpha = 0.25;
box(ax, 'off');
end
%% =========================================================================
%  PLOT 4 — Game length distribution
%% =========================================================================

function plot4_game_length(T2, T4, outDir, ts)
lens2 = T2.total_turns;
lens4 = T4.total_turns;
lens2 = lens2(~isnan(lens2) & lens2 > 0);
lens4 = lens4(~isnan(lens4) & lens4 > 0);

if isempty(lens2) && isempty(lens4)
    fprintf('Plot 4: no game length data, skipping.\n');
    return;
end

allLens = [lens2; lens4];
edges   = linspace(0, max(allLens) + 15, 30);

fig = figure('Visible','off','Position',[100 100 640 460]);
ax  = axes(fig);
hold(ax, 'on');

if ~isempty(lens2)
    histogram(ax, lens2, edges, 'FaceColor', [0.35 0.60 0.88], ...
              'FaceAlpha', 0.65, 'EdgeColor', 'w', 'DisplayName', '2-player');
    xline(ax, mean(lens2), '--', 'Color', [0.20 0.40 0.75], 'LineWidth', 1.5, ...
          'Label', sprintf('2p mean: %.0f', mean(lens2)), ...
          'LabelHorizontalAlignment', 'right', 'FontSize', 10);
end

if ~isempty(lens4)
    histogram(ax, lens4, edges, 'FaceColor', [0.95 0.60 0.25], ...
              'FaceAlpha', 0.65, 'EdgeColor', 'w', 'DisplayName', '4-player');
    xline(ax, mean(lens4), '--', 'Color', [0.80 0.38 0.08], 'LineWidth', 1.5, ...
          'Label', sprintf('4p mean: %.0f', mean(lens4)), ...
          'LabelHorizontalAlignment', 'left', 'FontSize', 10);
end

xlabel(ax, 'Total Turns', 'FontSize', 13);
ylabel(ax, 'Games', 'FontSize', 13);
title(ax, 'Game Length Distribution by Player Count', 'FontSize', 13);
legend(ax, 'Location', 'northeast', 'FontSize', 11);
grid(ax, 'on');
ax.GridAlpha = 0.25;
ax.FontSize  = 11;
box(ax, 'off');

saveas(fig, fullfile(outDir, [ts '_plot4_game_length.png']));
close(fig);
fprintf('Plot 4 saved.\n');
end

%% =========================================================================
%  SUMMARY
%% =========================================================================

function print_summary(T2, T4, agents, nA)
matchups2 = unique(T2.matchup);
fprintf('2-player matchups:\n');
for m = 1:numel(matchups2)
    sub = T2(T2.matchup == matchups2(m), :);
    n   = height(sub);
    fprintf('  %-35s %d games\n', char(matchups2(m)), n);
    for i = 1:nA
        w = sum(agentMatch(sub.winner_agent, agents{i}));
        if w > 0
            fprintf('    %s wins: %d / %d (%.1f%%)\n', ...
                agents{i}, w, n, 100*w/n);
        end
    end
end

fprintf('\n4-player (%d games):\n', height(T4));
for i = 1:nA
    w = sum(agentMatch(T4.winner_agent, agents{i}));
    fprintf('  %-15s %d wins (%.1f%%)\n', agents{i}, w, 100*w/height(T4));
end

if ~isempty(T2)
    fprintf('\nMean game length 2p: %.1f turns\n', mean(T2.total_turns));
end
if ~isempty(T4)
    fprintf('Mean game length 4p: %.1f turns\n', mean(T4.total_turns));
end
end

%% =========================================================================
%  HELPERS
%% =========================================================================

function tf = agentMatch(colData, agentName)
%AGENTMATCH  Robust agent name comparison for char, cellstr, and string arrays.
if isstring(colData)
    tf = colData == string(agentName);
elseif iscell(colData)
    tf = strcmp(colData, agentName);
else
    % scalar string or char array — convert via cellstr
    try
        tf = strcmp(cellstr(colData), agentName);
    catch
        tf = false(size(colData));
    end
end
end

function c = agentColor(i)
colors = [0.29 0.55 0.89;   % random      — blue
          0.22 0.72 0.45;   % heuristic   — green
          0.95 0.60 0.22;   % monte_carlo — orange
          0.75 0.30 0.50];  % mcts        — purple
c = colors(mod(i-1, size(colors,1)) + 1, :);
end