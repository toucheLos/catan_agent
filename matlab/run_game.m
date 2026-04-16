%RUN_GAME  Single-game runner with per-turn logging and VP chart.
%
%   Runs one full game (heuristic vs mcts, no display).
%   Saves timestamped outputs to matlab/outputs/:
%     YYYYMMDD_HHMMSS_game_log.csv
%     YYYYMMDD_HHMMSS_vp_over_time.png
%
%   Run:  run_game

%% ── PARAMS ───────────────────────────────────────────────────────────────────
PARAMS.agents  = {'heuristic', 'mcts'};
PARAMS.rngSeed = 42;

%% ── Setup ────────────────────────────────────────────────────────────────────
ts        = datestr(now, 'yyyymmdd_HHMMSS');  %#ok<TNOW1,DATST>
outputDir = fullfile(fileparts(mfilename('fullpath')), 'outputs');
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

config                = catan_core('defaultConfig');
config.showViz        = false;
config.pauseAfterMove = false;
config.verbose        = false;
config.rngSeed        = PARAMS.rngSeed;

agentNames = PARAMS.agents;
agentFnMap = containers.Map( ...
    {'random','heuristic','monte_carlo','mcts'}, ...
    {@agent_random, @agent_heuristic, @agent_montecarlo, @agent_mcts});

agentFns = cellfun(@(n) agentFnMap(n), agentNames, 'UniformOutput', false);
config.numPlayers = numel(agentFns);

%% ── Run game ─────────────────────────────────────────────────────────────────
history = catan_core('simulateGame', agentFns, config, agentNames);
fs      = history.finalState;

%% ── Console output ───────────────────────────────────────────────────────────
winId   = fs.winnerId;
if winId >= 1 && winId <= numel(agentNames)
    winName = agentNames{winId};
else
    winName = 'None';
end

fprintf('\nGame over!\n');
fprintf('Winner     : %s (Player %d)\n', winName, winId);
fprintf('Total turns: %d\n', fs.turnIndex);
for p = 1:numel(agentNames)
    fprintf('  P%d (%s): %d VP\n', p, agentNames{p}, fs.players(p).victoryPoints);
end

%% ── game_log.csv ─────────────────────────────────────────────────────────────
fid = fopen(fullfile(outputDir, sprintf('%s_game_log.csv', ts)), 'w');
fprintf(fid, 'turn,player_id,agent_type,action_type,vp_after\n');
for k = 1:numel(history.actions)
    e = history.actions(k);
    fprintf(fid, '%d,%d,%s,%s,%d\n', ...
        e.turn, e.player, agentNames{e.player}, e.type, e.vp);
end
fclose(fid);

%% ── vp_over_time.png ─────────────────────────────────────────────────────────
% Group actions by player to build per-agent VP time series.
% Each recorded entry is the acting player's VP after their action.
% stairs() draws a step function that stays flat between data points.

palette = [0.357 0.608 0.835;   % muted blue
           0.929 0.490 0.192];  % muted orange

fig2 = figure('Visible','off','Position',[0 0 820 420]);
ax2  = axes(fig2);
hold(ax2, 'on');

for p = 1:numel(agentNames)
    mask = [history.actions.player] == p;
    if ~any(mask), continue; end
    entries = history.actions(mask);
    turns   = [entries.turn];
    vps     = [entries.vp];
    stairs(ax2, turns, vps, ...
        'Color',    palette(mod(p-1, size(palette,1))+1, :), ...
        'LineWidth', 2, ...
        'DisplayName', agentNames{p});
end

hold(ax2, 'off');
legend(ax2, 'Location','northwest');
xlabel(ax2, 'Turn');
ylabel(ax2, 'Victory Points');
title(ax2, 'VP Progression');
ax2.YGrid         = 'on';
ax2.XGrid         = 'off';
ax2.GridLineStyle = '--';
ax2.GridAlpha     = 0.4;
ax2.TickLength    = [0, 0];
box(ax2, 'off');

print(fig2, fullfile(outputDir, sprintf('%s_vp_over_time.png', ts)), '-dpng', '-r150');
close(fig2);

fprintf('\n  Outputs saved to: %s\n', outputDir);
fprintf('  Timestamp prefix: %s\n\n', ts);
