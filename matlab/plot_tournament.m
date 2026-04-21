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
nA     = numel(agents);

T2 = T(T.player_count == 2, :);
T4 = T(T.player_count == 4, :);

timestamp = char(datetime('now','Format','yyyyMMdd_HHmmss'));

plot1_pairwise_heatmap(T2, agents, nA, outputDir, timestamp);
plot2_4p_winrate(T4, agents, nA, outputDir, timestamp);
plot3_vp_boxplot(T2, T4, agents, nA, outputDir, timestamp);
plot4_game_length(T2, T4, outputDir, timestamp);

fprintf('\nPlots saved to: %s/\n', outputDir);
end

%% =========================================================================

function plot1_pairwise_heatmap(T2, agents, nA, outDir, ts)
winMat = zeros(nA, nA);  % winMat(i,j) = win rate of agent i vs agent j

for i = 1:nA
    for j = 1:nA
        if i == j
            winMat(i,j) = 0.5;
            continue;
        end
        ai = agents{i}; aj = agents{j};
        % Rows where this exact pair played
        mask = (contains(T2.matchup, ai) & contains(T2.matchup, aj));
        sub  = T2(mask, :);
        if isempty(sub), winMat(i,j) = NaN; continue; end

        % Identify which column is agent i
        wins = 0; seats = 0;
        for r = 1:height(sub)
            for p = 1:2
                col = sprintf('p%d_agent', p);
                if strcmp(sub.(col)(r), ai)
                    seats = seats + 1;
                    if strcmp(sub.winner_agent(r), ai)
                        wins = wins + 1;
                    end
                end
            end
        end
        winMat(i,j) = wins / max(seats, 1);
    end
end

fig = figure('Visible','off','Position',[100 100 560 460]);
imagesc(winMat, [0 1]);
colormap(parula);
cb = colorbar;
cb.Label.String = 'Win Rate';
hold on;
for i = 1:nA
    for j = 1:nA
        if isnan(winMat(i,j)), continue; end
        clr = 'w';
        if winMat(i,j) > 0.3 && winMat(i,j) < 0.7, clr = 'k'; end
        text(j, i, sprintf('%.2f', winMat(i,j)), ...
            'HorizontalAlignment','center','Color',clr,'FontSize',11,'FontWeight','bold');
    end
end
set(gca,'XTick',1:nA,'XTickLabel',agents,'XTickLabelRotation',30, ...
        'YTick',1:nA,'YTickLabel',agents,'TickLabelInterpreter','none');
xlabel('Opponent'); ylabel('Agent');
title('1v1 Pairwise Win Rate (row agent vs column agent)');
saveas(fig, fullfile(outDir, [ts '_plot1_pairwise_heatmap.png']));
close(fig);
fprintf('Plot 1 saved.\n');
end

%% =========================================================================

function plot2_4p_winrate(T4, agents, nA, outDir, ts)
if isempty(T4)
    fprintf('Plot 2: no 4-player data, skipping.\n'); return;
end

wins  = zeros(1, nA);
seats = zeros(1, nA);
for i = 1:nA
    for p = 1:4
        col = sprintf('p%d_agent', p);
        if ~any(strcmp(T4.Properties.VariableNames, col)), continue; end
        mask = strcmp(T4.(col), agents{i});
        seats(i) = seats(i) + sum(mask);
        wins(i)  = wins(i)  + sum(mask & strcmp(T4.winner_agent, agents{i}));
    end
end

wr = wins ./ max(seats, 1);
% 95% CI via Wilson interval
ci = zeros(1, nA);
for i = 1:nA
    if seats(i) == 0, continue; end
    p = wr(i); n = seats(i);
    ci(i) = 1.96 * sqrt(p*(1-p)/n);
end

fig = figure('Visible','off','Position',[100 100 520 420]);
b = bar(1:nA, wr, 0.5, 'FaceColor','flat');
for i = 1:nA, b.CData(i,:) = agentColor(i); end
hold on;
errorbar(1:nA, wr, ci, 'k.', 'LineWidth', 1.4);
yline(0.25, '--', 'Chance (25%)', 'Color',[0.5 0.5 0.5]);
set(gca,'XTick',1:nA,'XTickLabel',agents,'TickLabelInterpreter','none');
ylabel('Win Rate'); ylim([0 min(1, max(wr + ci)*1.3 + 0.05)]);
title(sprintf('4-Player Win Rate with 95%% CI  (n=%d games)', max(seats)));
grid on;
saveas(fig, fullfile(outDir, [ts '_plot2_4p_winrate.png']));
close(fig);
fprintf('Plot 2 saved.\n');
end

%% =========================================================================

function plot3_vp_boxplot(T2, T4, agents, nA, outDir, ts)
fig = figure('Visible','off','Position',[100 100 900 420]);

% 1v1 VP
subplot(1,2,1);
vpData = cell(1, nA);
for i = 1:nA
    vp = [];
    for p = 1:2
        col = sprintf('p%d_agent', p);
        vpcol = sprintf('p%d_vp', p);
        if ~any(strcmp(T2.Properties.VariableNames, col)), continue; end
        mask = strcmp(T2.(col), agents{i});
        vp = [vp; T2.(vpcol)(mask)]; %#ok<AGROW>
    end
    vpData{i} = vp;
end
plotBoxGroups(vpData, agents, '1v1 VP Distribution');

% 4-player VP
subplot(1,2,2);
vpData4 = cell(1, nA);
for i = 1:nA
    vp = [];
    for p = 1:4
        col = sprintf('p%d_agent', p);
        vpcol = sprintf('p%d_vp', p);
        if ~any(strcmp(T4.Properties.VariableNames, col)), continue; end
        mask = strcmp(T4.(col), agents{i});
        vp = [vp; T4.(vpcol)(mask)]; %#ok<AGROW>
    end
    vpData4{i} = vp;
end
plotBoxGroups(vpData4, agents, '4-Player VP Distribution');

saveas(fig, fullfile(outDir, [ts '_plot3_vp_boxplots.png']));
close(fig);
fprintf('Plot 3 saved.\n');
end

function plotBoxGroups(vpData, agents, titleStr)
allVP  = [];
groups = {};
for i = 1:numel(agents)
    if isempty(vpData{i}), continue; end
    allVP  = [allVP;  vpData{i}]; %#ok<AGROW>
    groups = [groups; repmat(agents(i), numel(vpData{i}), 1)]; %#ok<AGROW>
end
if isempty(allVP), title(titleStr); return; end
boxplot(allVP, groups, 'GroupOrder', agents);
ylabel('Final VP'); title(titleStr); grid on;
end

%% =========================================================================

function plot4_game_length(T2, T4, outDir, ts)
lens2 = T2.total_turns;
lens4 = T4.total_turns;
lens2 = lens2(~isnan(lens2) & lens2 > 0);
lens4 = lens4(~isnan(lens4) & lens4 > 0);

if isempty(lens2) && isempty(lens4)
    fprintf('Plot 4: no game length data, skipping.\n'); return;
end

fig = figure('Visible','off','Position',[100 100 600 420]);
hold on;
edges = 0:10:max([lens2; lens4]) + 10;
if ~isempty(lens2)
    histogram(lens2, edges, 'FaceAlpha', 0.6, 'DisplayName', '2-player');
end
if ~isempty(lens4)
    histogram(lens4, edges, 'FaceAlpha', 0.6, 'DisplayName', '4-player');
end
xlabel('Total Turns'); ylabel('Games');
title('Game Length Distribution by Player Count');
legend('Location','northeast');
grid on;
saveas(fig, fullfile(outDir, [ts '_plot4_game_length.png']));
close(fig);
fprintf('Plot 4 saved.\n');
end

%% =========================================================================

function c = agentColor(i)
colors = [0.29 0.55 0.89;   % blue
          0.22 0.72 0.45;   % green
          0.95 0.60 0.22;   % orange
          0.85 0.33 0.33];  % red
c = colors(mod(i-1, size(colors,1)) + 1, :);
end
