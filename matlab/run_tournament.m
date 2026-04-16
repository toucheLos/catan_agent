%RUN_TOURNAMENT  Presentation tournament runner: heuristic vs mcts, round-robin.
%
%   Saves timestamped outputs to matlab/outputs/:
%     YYYYMMDD_HHMMSS_win_rates.csv
%     YYYYMMDD_HHMMSS_win_rate_chart.png
%     YYYYMMDD_HHMMSS_avg_game_length.csv
%     YYYYMMDD_HHMMSS_vp_final.csv
%
%   Edit PARAMS below, then run:  run_tournament

%% ── PARAMS ───────────────────────────────────────────────────────────────────
PARAMS.agents  = {'heuristic', 'mcts'};
PARAMS.N       = 50;   % games per ordered matchup
PARAMS.rngSeed = 1;    % base seed (incremented per game for variety)

%% ── Setup ────────────────────────────────────────────────────────────────────
ts        = datestr(now, 'yyyymmdd_HHMMSS');  %#ok<TNOW1,DATST>
outputDir = fullfile(fileparts(mfilename('fullpath')), 'outputs');
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

config                = catan_core('defaultConfig');
config.showViz        = false;
config.pauseAfterMove = false;
config.verbose        = false;

agentNames = PARAMS.agents;
N          = PARAMS.N;
nAgents    = numel(agentNames);

agentFnMap = containers.Map( ...
    {'random','heuristic','monte_carlo','mcts'}, ...
    {@agent_random, @agent_heuristic, @agent_montecarlo, @agent_mcts});

% Accumulators
wins        = zeros(1, nAgents);
losses      = zeros(1, nAgents);
gameLengths = [];
vpByAgent   = cell(1, nAgents);   % final VP per game per agent

% All ordered pairs (i,j) where i ~= j
matchups = [];
for ii = 1:nAgents
    for jj = 1:nAgents
        if ii ~= jj
            matchups(end+1,:) = [ii, jj]; %#ok<AGROW>
        end
    end
end

fprintf('\n%s\n', repmat('=',1,54));
fprintf('  TOURNAMENT  (%d games per ordered matchup)\n', N);
fprintf('  Agents: %s\n', strjoin(agentNames, ', '));
fprintf('%s\n', repmat('=',1,54));

baseRngSeed = PARAMS.rngSeed;
gameNum     = 0;

%% ── Round-robin ──────────────────────────────────────────────────────────────
for m = 1:size(matchups,1)
    iA     = matchups(m,1);
    iB     = matchups(m,2);
    p1Name = agentNames{iA};
    p2Name = agentNames{iB};
    p1Fn   = agentFnMap(p1Name);
    p2Fn   = agentFnMap(p2Name);

    fprintf('  %-15s (P1)  vs  %-15s (P2) ...', p1Name, p2Name);
    p1Wins = 0;

    for g = 1:N
        gameNum        = gameNum + 1;
        cfg            = config;
        cfg.rngSeed    = baseRngSeed + gameNum;

        history = catan_core('simulateGame', {p1Fn, p2Fn}, cfg);
        fs      = history.finalState;

        if fs.winnerId == 1
            wins(iA)   = wins(iA)   + 1;
            losses(iB) = losses(iB) + 1;
            p1Wins     = p1Wins + 1;
        elseif fs.winnerId == 2
            wins(iB)   = wins(iB)   + 1;
            losses(iA) = losses(iA) + 1;
        end

        gameLengths(end+1)     = fs.turnIndex; %#ok<AGROW>
        vpByAgent{iA}(end+1)   = fs.players(1).victoryPoints;
        vpByAgent{iB}(end+1)   = fs.players(2).victoryPoints;
    end

    fprintf('  %d/%d for P1\n', p1Wins, N);
end

%% ── Console summary ──────────────────────────────────────────────────────────
avgLen = mean(gameLengths);

fprintf('\n%s\n', repmat('=',1,54));
fprintf('  RESULTS\n');
fprintf('%s\n', repmat('=',1,54));
for i = 1:nAgents
    total = wins(i) + losses(i);
    rate  = wins(i) / max(total, 1);
    avgVP = mean(vpByAgent{i});
    fprintf('  %-15s: %dW / %dL  (%.1f%% win rate)  avg VP: %.2f\n', ...
        agentNames{i}, wins(i), losses(i), rate*100, avgVP);
end
fprintf('  Avg game length : %.1f turns\n', avgLen);
fprintf('  Total games     : %d\n\n', numel(gameLengths));

%% ── win_rates.csv ────────────────────────────────────────────────────────────
fid = fopen(fullfile(outputDir, sprintf('%s_win_rates.csv', ts)), 'w');
fprintf(fid, 'agent,wins,losses,win_rate\n');
for i = 1:nAgents
    total = wins(i) + losses(i);
    rate  = wins(i) / max(total,1);
    fprintf(fid, '%s,%d,%d,%.4f\n', agentNames{i}, wins(i), losses(i), rate);
end
fclose(fid);

%% ── win_rate_chart.png ───────────────────────────────────────────────────────
rates = zeros(1, nAgents);
for i = 1:nAgents
    total    = wins(i) + losses(i);
    rates(i) = wins(i) / max(total, 1);
end

% Muted palette: blue, orange, green, gold
palette = [0.357 0.608 0.835;
           0.929 0.490 0.192;
           0.439 0.678 0.278;
           1.000 0.753 0.000];

fig1 = figure('Visible','off','Position',[0 0 520 440]);
ax1  = axes(fig1);
b    = bar(ax1, 1:nAgents, rates, 0.5);
b.FaceColor = 'flat';
for i = 1:nAgents
    b.CData(i,:) = palette(mod(i-1, size(palette,1))+1, :);
end
ax1.XTick      = 1:nAgents;
ax1.XTickLabel = agentNames;
ax1.YLim       = [0, 1.15];
ax1.YGrid      = 'on';
ax1.XGrid      = 'off';
ax1.GridLineStyle = '--';
ax1.GridAlpha  = 0.4;
ax1.TickLength = [0, 0];
box(ax1, 'off');
ylabel(ax1, 'Win Rate');
title(ax1, sprintf('Agent Win Rates  (N=%d total games)', numel(gameLengths)));
for i = 1:nAgents
    text(ax1, i, rates(i) + 0.03, sprintf('%.1f%%', rates(i)*100), ...
        'HorizontalAlignment','center','FontSize',11,'FontWeight','bold');
end
print(fig1, fullfile(outputDir, sprintf('%s_win_rate_chart.png', ts)), '-dpng', '-r150');
close(fig1);

%% ── avg_game_length.csv ──────────────────────────────────────────────────────
fid = fopen(fullfile(outputDir, sprintf('%s_avg_game_length.csv', ts)), 'w');
fprintf(fid, 'metric,value\n');
fprintf(fid, 'avg_turns,%.2f\n', avgLen);
fprintf(fid, 'min_turns,%d\n',   min(gameLengths));
fprintf(fid, 'max_turns,%d\n',   max(gameLengths));
fprintf(fid, 'total_games,%d\n', numel(gameLengths));
fclose(fid);

%% ── vp_final.csv ─────────────────────────────────────────────────────────────
fid = fopen(fullfile(outputDir, sprintf('%s_vp_final.csv', ts)), 'w');
fprintf(fid, 'agent,avg_vp\n');
for i = 1:nAgents
    fprintf(fid, '%s,%.4f\n', agentNames{i}, mean(vpByAgent{i}));
end
fclose(fid);

fprintf('  Outputs saved to: %s\n', outputDir);
fprintf('  Timestamp prefix: %s\n\n', ts);
