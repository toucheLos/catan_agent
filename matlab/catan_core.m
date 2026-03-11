function varargout = catan_core(command, varargin)
%CATAN_CORE  Settlements-only Catan game engine (single-file MATLAB module).
%
% Start a game by running with no arguments:
%   catan_core
%
% Or call specific commands:
%   config  = catan_core('defaultConfig')
%   history = catan_core('simulateGame', agentFns, config)
%   legal   = catan_core('enumerateLegalActions', state, playerId, config)
%   state   = catan_core('applyAction', state, playerId, action, config)
%   [done, winnerId] = catan_core('checkTerminal', state, config)
%   state   = catan_core('distributeResources', state, roll, config)
%   roll    = catan_core('rollDice')
%   action  = catan_core('makeAction', type, vertexId)
%   tf      = catan_core('isLegalAction', action, legalActions)
%   p       = catan_core('diceProbability', n)

if nargin == 0
    runGame();
    return;
end

switch lower(command)
    case 'defaultconfig'
        varargout{1} = defaultConfig();
    case 'simulategame'
        varargout{1} = simulateGame(varargin{:});
    case 'enumeratelegalactions'
        varargout{1} = enumerateLegalActions(varargin{:});
    case 'applyaction'
        varargout{1} = applyAction(varargin{:});
    case 'checkterminal'
        [varargout{1}, varargout{2}] = checkTerminal(varargin{:});
    case 'distributeresources'
        varargout{1} = distributeResources(varargin{:});
    case 'rolldice'
        varargout{1} = rollDice();
    case 'makeaction'
        varargout{1} = makeAction(varargin{:});
    case 'islegalaction'
        varargout{1} = isLegalAction(varargin{:});
    case 'diceprobability'
        varargout{1} = diceProbability(varargin{1});
    case 'rungame'
        runGame();
    case 'runtournament'
        varargout{1} = runTournament(varargin{:});
    otherwise
        error('Unknown catan_core command: %s', command);
end

end

%% ========================= ENTRY POINT =========================

function runGame()
%RUNGAME  Main entry point. Edit PARAMS below, then run: catan_core
%
% Player types:
%   'random'      - picks a uniformly random legal action each turn
%   'heuristic'   - greedy placement scored by production value and diversity
%   'monte_carlo' - flat Monte Carlo rollouts to evaluate candidate actions
%   'live'        - you play interactively via keyboard input

% =========================================================================
%  PARAMETERS — edit these to configure your game
% =========================================================================

% Players in turn order. Use any combination of the four types above.
% Example with you playing: {'random', 'heuristic', 'live'}
PARAMS.players = {'random', 'heuristic'};

% Pause after each AI move so you can follow the game step by step.
% Live player turns always pause for input regardless of this setting.
PARAMS.pauseAfterMove = true;

% RNG seed for reproducibility. Set to 0 for a different board each run.
PARAMS.rngSeed = 42;

% First player to reach this many settlements wins.
PARAMS.winSettlements = 8;

% Hard cap on turns to prevent infinite games.
PARAMS.maxTurns = 200;

% Monte Carlo settings (only matter if 'monte_carlo' is one of the players).
PARAMS.mc.rolloutCount          = 20;          % rollouts per candidate action
PARAMS.mc.rolloutHorizon        = 30;          % max simulated turns per rollout
PARAMS.mc.selfRolloutPolicy     = 'heuristic'; % policy for self during rollouts
PARAMS.mc.opponentRolloutPolicy = 'random';    % policy for opponents in rollouts

% Show the board visualization window.
PARAMS.showViz = true;

% =========================================================================

config                = defaultConfig();
config.rngSeed        = PARAMS.rngSeed;
config.winSettlements = PARAMS.winSettlements;
config.maxTurns       = PARAMS.maxTurns;
config.pauseAfterMove = PARAMS.pauseAfterMove;
config.showViz        = PARAMS.showViz;
config.rolloutCount   = PARAMS.mc.rolloutCount;
config.rolloutHorizon = PARAMS.mc.rolloutHorizon;
config.mc             = PARAMS.mc;

numPlayers = numel(PARAMS.players);
agentFns   = cell(1, numPlayers);
for i = 1:numPlayers
    switch lower(PARAMS.players{i})
        case 'random'
            agentFns{i} = @agent_random;
        case 'heuristic'
            agentFns{i} = @agent_heuristic;
        case 'monte_carlo'
            agentFns{i} = @agent_montecarlo;
        case 'mcts'
            agentFns{i} = @agent_mcts;
        case 'live'
            agentFns{i} = @agent_live;
        otherwise
            error('Unknown player type "%s". Choose from: random, heuristic, monte_carlo, mcts, live.', ...
                PARAMS.players{i});
    end
end

fprintf('\n========================================\n');
fprintf('         CATAN SIMULATION\n');
fprintf('========================================\n');
for i = 1:numPlayers
    fprintf('  Player %d: %s\n', i, PARAMS.players{i});
end
fprintf('  Win at:    %d settlements\n', config.winSettlements);
fprintf('  Max turns: %d\n', config.maxTurns);
fprintf('========================================\n\n');

history = simulateGame(agentFns, config, PARAMS.players);

fprintf('\n========================================\n');
fprintf('              GAME OVER\n');
fprintf('========================================\n');
if history.finalState.winnerId ~= 0
    wId = history.finalState.winnerId;
    fprintf('  Winner: Player %d (%s) with %d settlements!\n', ...
        wId, PARAMS.players{wId}, history.finalState.players(wId).settlementCount);
else
    fprintf('  No winner — max turns reached.\n');
end
fprintf('  Total turns: %d\n', history.finalState.turnIndex);
fprintf('  Final standings:\n');
for p = 1:numPlayers
    fprintf('    P%d (%s): %d VP\n', p, PARAMS.players{p}, ...
        history.finalState.players(p).victoryPoints);
end
fprintf('========================================\n');
end

%% Configuration

function config = defaultConfig()
%DEFAULTCONFIG  Returns a struct of all tunable engine parameters.

config.numPlayers             = 2;
config.maxTurns               = 200;
config.winSettlements         = 8;
config.resourceNames          = {'wood', 'brick', 'sheep', 'wheat', 'ore'};
config.buildCosts.settlement  = [1 1 1 1 0];
config.initialResources       = [0 0 0 0 0];
config.initialFreeSettlements = 2;
config.enforceDistanceRule    = true;
config.rngSeed                = 42;
config.pauseAfterMove         = false;
config.showViz                = true;
config.rolloutCount           = 20;
config.rolloutHorizon         = 30;
config.mc.selfRolloutPolicy     = 'heuristic';
config.mc.opponentRolloutPolicy = 'random';
% Verbose: set false to suppress per-turn console output (e.g. in tournament).
config.verbose                  = true;
% Heuristic agent tunable weights (override via config.heuristic.*).
config.heuristic.wExpectedProduction = 3.0;
config.heuristic.wResourceNeed       = 1.5;
config.heuristic.wDiversity          = 1.0;
config.heuristic.wBlocking           = 0.2;
% MCTS exploration constant (UCB1).
config.mcts.C = sqrt(2);
end

%% ------------------------- Game Loop -------------------------

function history = simulateGame(agentFns, config, playerNames)
%SIMULATEGAME  Runs one complete game and returns a history struct.

if nargin < 3 || isempty(playerNames)
    playerNames = arrayfun(@(p) sprintf('P%d', p), 1:numel(agentFns), 'UniformOutput', false);
end
if nargin < 2 || isempty(config)
    config = defaultConfig();
end

config.numPlayers = numel(agentFns);
doPause   = isfield(config, 'pauseAfterMove') && config.pauseAfterMove;
useViz    = isfield(config, 'showViz') && config.showViz;
doVerbose = ~isfield(config, 'verbose') || config.verbose;

state = initGame(config);

% Create visualization window before placement so user sees the board.
fig = [];
if useViz
    fig = initGameFig(state, config, playerNames);
end

state = initialPlacement(state, agentFns, config, playerNames, doPause, fig);

history        = struct();
history.actions = struct('turn', {}, 'player', {}, 'roll', {}, 'type', {}, 'vertexId', {}, 'vp', {});
history.logs   = {};

while ~state.isTerminal

    playerId = state.currentPlayer;

    state.lastRoll = rollDice();
    state = distributeResources(state, state.lastRoll, config);

    if doVerbose
        fprintf('----------------------------------------\n');
        fprintf('Turn %d | Player %d (%s) | Roll: %d\n', ...
            state.turnIndex, playerId, playerNames{playerId}, state.lastRoll);
        printPlayerResources(state, playerId, config);
    end

    history.logs{end + 1} = sprintf('Turn %d | P%d rolled %d', ...
        state.turnIndex, playerId, state.lastRoll); %#ok<AGROW>

    legalActions = enumerateLegalActions(state, playerId, config);

    % For live player: highlight legal vertices on the board.
    if useViz && ishandle(fig) && strcmp(playerNames{playerId}, 'live')
        highlightLegalActions(fig, legalActions, state);
    end

    action = agentFns{playerId}(state, legalActions, playerId, config);

    if ~isLegalAction(action, legalActions)
        action = makeAction('pass', 0);
    end

    state = applyAction(state, playerId, action, config);

    logLine = sprintf('P%d (%s) -> %s', playerId, playerNames{playerId}, action.type);
    if strcmp(action.type, 'build_settlement')
        logLine = sprintf('%s @v%d', logLine, action.vertexId);
    end
    logLine = sprintf('%s | VP=%d', logLine, state.players(playerId).victoryPoints);
    if doVerbose
        fprintf('%s\n', logLine);
    end

    history.logs{end + 1} = logLine; %#ok<AGROW>
    history.actions(end + 1) = struct( ... %#ok<AGROW>
        'turn',     state.turnIndex, ...
        'player',   playerId, ...
        'roll',     state.lastRoll, ...
        'type',     action.type, ...
        'vertexId', action.vertexId, ...
        'vp',       state.players(playerId).victoryPoints);

    % Update visualization.
    if useViz && ishandle(fig)
        updateGameFig(fig, state, config, playerNames, playerId, logLine, state.lastRoll);
    end

    [done, winnerId] = checkTerminal(state, config);
    state.isTerminal = done;
    state.winnerId   = winnerId;

    if state.isTerminal
        break;
    end

    % Pause after AI moves (live player already paused for keyboard input).
    if doPause && ~strcmp(playerNames{playerId}, 'live')
        input('  [Press Enter to continue]', 's');
    end

    state.currentPlayer = mod(playerId, config.numPlayers) + 1;
    state.turnIndex     = state.turnIndex + 1;

    [done, winnerId] = checkTerminal(state, config);
    state.isTerminal = done;
    state.winnerId   = winnerId;
end

history.finalState = state;
end

%% ------------------------- State Initialization -------------------------

function state = initGame(config)
%INITGAME  Seeds RNG, builds board, initializes players, sets counters.

rng(config.rngSeed, 'twister');

board        = createCatanBoard();
numPlayers   = config.numPlayers;
numResources = numel(config.resourceNames);

players = repmat(struct( ...
    'id',              0, ...
    'resources',       zeros(1, numResources), ...
    'settlementCount', 0, ...
    'victoryPoints',   0), 1, numPlayers);

for p = 1:numPlayers
    players(p).id        = p;
    players(p).resources = config.initialResources;
end

state               = struct();
state.turnIndex     = 1;
state.currentPlayer = 1;
state.board         = board;
state.players       = players;
state.lastRoll      = 0;
state.isTerminal    = false;
state.winnerId      = 0;
end

%% ------------------------- Initial Placement -------------------------

function state = initialPlacement(state, agentFns, config, playerNames, doPause, fig)
%INITIALPLACEMENT  Each player places K free settlements before the game starts.

P = config.numPlayers;
K = config.initialFreeSettlements;
useViz    = ~isempty(fig);
doVerbose = ~isfield(config, 'verbose') || config.verbose;

if doVerbose
    fprintf('=== Initial Placement (%d free settlement(s) each) ===\n', K);
end

for round = 1:K
    for p = 1:P
        legal = enumerateLegalActionsFree(state, config);

        if doVerbose
            fprintf('  [Round %d] Player %d (%s) placing...\n', round, p, playerNames{p});
        end

        % For live player: highlight legal vertices before they choose.
        if useViz && ishandle(fig) && strcmp(playerNames{p}, 'live')
            highlightLegalActions(fig, legal, state);
        end

        a = agentFns{p}(state, legal, p, config);

        if ~isLegalAction(a, legal)
            if numel(legal) > 1
                a = legal(2);
            else
                a = makeAction('pass', 0);
            end
        end

        state = applyActionFree(state, p, a, config);

        if strcmp(a.type, 'build_settlement')
            if doVerbose
                fprintf('    P%d placed settlement at vertex %d\n', p, a.vertexId);
            end
            statusStr = sprintf('Placement: P%d (%s) placed @v%d', p, playerNames{p}, a.vertexId);
        else
            if doVerbose
                fprintf('    P%d passed placement\n', p);
            end
            statusStr = sprintf('Placement: P%d (%s) passed', p, playerNames{p});
        end

        if useViz && ishandle(fig)
            updateGameFig(fig, state, config, playerNames, p, statusStr, 0);
        end

        if doPause && ~strcmp(playerNames{p}, 'live')
            input('  [Press Enter to continue]', 's');
        end
    end
end

if doVerbose
    fprintf('=== Placement complete. Starting game. ===\n\n');
end
end

function legalActions = enumerateLegalActionsFree(state, config)
%ENUMERATELEGALACTIONSFREE  All legal initial placement actions (no resource cost).

legalActions = makeAction('pass', 0);
for v = 1:numel(state.board.vertices)
    if state.board.vertices(v).owner ~= 0
        continue;
    end
    if config.enforceDistanceRule
        neighbors = state.board.vertices(v).adjVertexIds;
        if any([state.board.vertices(neighbors).owner] ~= 0)
            continue;
        end
    end
    legalActions(end + 1) = makeAction('build_settlement', v); %#ok<AGROW>
end
end

function state = applyActionFree(state, playerId, action, config)
%APPLYACTIONFREE  Place a settlement for free (no resource deduction).

if ~strcmp(action.type, 'build_settlement')
    return;
end
v = action.vertexId;
if v < 1 || v > numel(state.board.vertices)
    return;
end
if state.board.vertices(v).owner ~= 0
    return;
end
if config.enforceDistanceRule
    neighbors = state.board.vertices(v).adjVertexIds;
    if any([state.board.vertices(neighbors).owner] ~= 0)
        return;
    end
end

state.board.vertices(v).owner           = playerId;
state.players(playerId).settlementCount = state.players(playerId).settlementCount + 1;
state.players(playerId).victoryPoints   = state.players(playerId).settlementCount;
end

%% ------------------------- Core Rules -------------------------

function roll = rollDice()
%ROLLDICE  Rolls two d6 and returns the sum (2..12).
roll = randi(6) + randi(6);
end

function state = distributeResources(state, roll, config)
%DISTRIBUTERESOURCES  Award +1 resource to each settlement on a hex matching roll.

for v = 1:numel(state.board.vertices)
    owner = state.board.vertices(v).owner;
    if owner == 0
        continue;
    end
    for h = state.board.vertices(v).adjHexIds
        if state.board.hexes(h).diceNumber == roll
            rType = state.board.hexes(h).resourceType;
            if strcmp(rType, 'desert')
                continue;
            end
            rIdx = resourceIndex(rType, config.resourceNames);
            state.players(owner).resources(rIdx) = state.players(owner).resources(rIdx) + 1;
        end
    end
end
end

function legalActions = enumerateLegalActions(state, playerId, config)
%ENUMERATELEGALACTIONS  Returns pass plus any affordable build_settlement actions.

legalActions = makeAction('pass', 0);
if ~canAfford(state.players(playerId).resources, config.buildCosts.settlement)
    return;
end
for v = 1:numel(state.board.vertices)
    if state.board.vertices(v).owner ~= 0
        continue;
    end
    if config.enforceDistanceRule
        neighbors = state.board.vertices(v).adjVertexIds;
        if any([state.board.vertices(neighbors).owner] ~= 0)
            continue;
        end
    end
    legalActions(end + 1) = makeAction('build_settlement', v); %#ok<AGROW>
end
end

function state = applyAction(state, playerId, action, config)
%APPLYACTION  Apply a normal turn action (pass or build settlement).

if strcmp(action.type, 'pass')
    return;
end
if ~strcmp(action.type, 'build_settlement')
    return;
end
v = action.vertexId;
if v < 1 || v > numel(state.board.vertices)
    return;
end
if state.board.vertices(v).owner ~= 0
    return;
end
if config.enforceDistanceRule
    neighbors = state.board.vertices(v).adjVertexIds;
    if any([state.board.vertices(neighbors).owner] ~= 0)
        return;
    end
end
cost = config.buildCosts.settlement;
if ~canAfford(state.players(playerId).resources, cost)
    return;
end

state.players(playerId).resources         = state.players(playerId).resources - cost;
state.board.vertices(v).owner             = playerId;
state.players(playerId).settlementCount   = state.players(playerId).settlementCount + 1;
state.players(playerId).victoryPoints     = state.players(playerId).settlementCount;
end

function [done, winnerId] = checkTerminal(state, config)
%CHECKTERMINAL  Returns done=true if win or turn cap reached.

done     = false;
winnerId = 0;
settlements = [state.players.settlementCount];
[maxS, maxIdx] = max(settlements);
if maxS >= config.winSettlements
    done     = true;
    winnerId = maxIdx;
    return;
end
if state.turnIndex > config.maxTurns
    done = true;
    [~, winnerId] = max([state.players.victoryPoints]);
end
end

%% ------------------------- Action Helpers -------------------------

function action = makeAction(type, vertexId)
%MAKEACTION  Constructs an action struct {type, vertexId}.
if nargin < 2
    vertexId = 0;
end
action = struct('type', type, 'vertexId', vertexId);
end

function tf = isLegalAction(action, legalActions)
%ISLEGALACTION  True if action matches any entry in legalActions.
tf = false;
for i = 1:numel(legalActions)
    if strcmp(action.type, legalActions(i).type) && action.vertexId == legalActions(i).vertexId
        tf = true;
        return;
    end
end
end

function p = diceProbability(n)
%DICEPROBABILITY  Probability that two d6 sum to n.
weights = [1 2 3 4 5 6 5 4 3 2 1];
if n < 2 || n > 12
    p = 0;
else
    p = weights(n - 1) / 36;
end
end

%% ------------------------- Utility Helpers -------------------------

function tf = canAfford(resources, cost)
%CANAFFORD  True if resources cover cost element-wise.
tf = all(resources >= cost);
end

function idx = resourceIndex(resourceType, resourceNames)
%RESOURCEINDEX  Maps a resource name to its vector index (1..5).
idx = find(strcmp(resourceNames, resourceType), 1);
if isempty(idx)
    error('Unknown resource type: %s', resourceType);
end
end

function printPlayerResources(state, playerId, config)
%PRINTPLAYERRESOURCES  Prints one players inventory and VP to the console.
res   = state.players(playerId).resources;
names = config.resourceNames;
parts = cell(1, numel(names));
for i = 1:numel(names)
    parts{i} = sprintf('%s:%d', names{i}, res(i));
end
fprintf('  Resources: %s | VP: %d\n', strjoin(parts, '  '), ...
    state.players(playerId).victoryPoints);
end

%% ------------------------- Live (Human) Agent -------------------------

function action = agent_live(state, legalActions, playerId, config)
%AGENT_LIVE  Interactive human player. Reads a numbered choice from keyboard.

fprintf('\n  *** Your turn, Player %d! ***\n', playerId);
res   = state.players(playerId).resources;
names = config.resourceNames;
fprintf('  Resources: ');
for i = 1:numel(names)
    fprintf('%s=%d  ', names{i}, res(i));
end
fprintf('\n  VP: %d\n\n', state.players(playerId).victoryPoints);

fprintf('  Legal actions:\n');
for i = 1:numel(legalActions)
    a = legalActions(i);
    if strcmp(a.type, 'pass')
        fprintf('    %d) pass\n', i);
    else
        v   = a.vertexId;
        pos = state.board.vertices(v).pos;
        fprintf('    %d) build_settlement  vertex %d  (x=%.2f, y=%.2f)\n', ...
            i, v, pos(1), pos(2));
    end
end

choice = 0;
while choice < 1 || choice > numel(legalActions) || isnan(choice)
    raw    = input('\n  Enter action number: ', 's');
    choice = str2double(raw);
    if isnan(choice) || choice < 1 || choice > numel(legalActions)
        fprintf('  Invalid — enter a number from 1 to %d.\n', numel(legalActions));
        choice = 0;
    end
end

action = legalActions(choice);
end

%% ========================= VISUALIZATION =========================

function fig = initGameFig(state, config, playerNames)
%INITGAMEFIG  Creates the Catan game visualization window.

fig = figure( ...
    'Name',        'Catan Simulation', ...
    'NumberTitle', 'off', ...
    'Color',       [0.10 0.13 0.20], ...
    'Position',    [60 60 1300 740]);

% Board axes — left 62% of the window.
ax_board = axes('Parent', fig, ...
    'Position',  [0.02 0.04 0.60 0.94], ...
    'Color',     [0.16 0.34 0.60], ...
    'XColor',    'none', ...
    'YColor',    'none', ...
    'Tag',       'board');
axis(ax_board, 'equal');
hold(ax_board, 'on');

% Info panel axes — right 35% of the window.
ax_info = axes('Parent', fig, ...
    'Position',  [0.64 0.04 0.35 0.94], ...
    'Color',     [0.08 0.10 0.16], ...
    'XColor',    'none', ...
    'YColor',    'none', ...
    'Tag',       'info');
hold(ax_info, 'on');

drawBoard(ax_board, state, config);
drawInfoPanel(ax_info, state, config, playerNames, 0, 'Setting up board...', 0);
drawnow;
end

function updateGameFig(fig, state, config, playerNames, currentPlayerId, actionStr, rollNum)
%UPDATEGAMEFIG  Redraws both panels with current game state.

if ~ishandle(fig)
    return;
end

ax_board = findobj(fig, 'Tag', 'board');
ax_info  = findobj(fig, 'Tag', 'info');

cla(ax_board);
cla(ax_info);

drawBoard(ax_board, state, config);
drawInfoPanel(ax_info, state, config, playerNames, currentPlayerId, actionStr, rollNum);
drawnow;
end

function highlightLegalActions(fig, legalActions, state)
%HIGHLIGHTLEGALACTIONS  Overlays yellow rings on legal build vertices.
%                       Called before the live player picks an action.

if ~ishandle(fig)
    return;
end
ax_board = findobj(fig, 'Tag', 'board');

for i = 1:numel(legalActions)
    if strcmp(legalActions(i).type, 'build_settlement')
        v   = legalActions(i).vertexId;
        pos = state.board.vertices(v).pos;
        plot(ax_board, pos(1), pos(2), 'o', ...
            'MarkerSize',      20, ...
            'MarkerFaceColor', 'none', ...
            'MarkerEdgeColor', [1.0 0.95 0.15], ...
            'LineWidth',       2.5);
    end
end
drawnow;
end

% -----------------------------------------------------------------
%  Board renderer
% -----------------------------------------------------------------

function drawBoard(ax, state, config)
%DRAWBOARD  Renders hex tiles, dice tokens, vertex IDs, and settlements.

hold(ax, 'on');
axis(ax, 'equal');
axis(ax, 'off');
set(ax, 'Color', [0.16 0.34 0.60]);

board = state.board;

% --- Hex tiles ---
for h = 1:numel(board.hexes)
    hex  = board.hexes(h);
    vIds = hex.vertexIds;

    % Collect the 6 corner positions in polygon order.
    xs = zeros(6, 1);
    ys = zeros(6, 1);
    for k = 1:6
        xs(k) = board.vertices(vIds(k)).pos(1);
        ys(k) = board.vertices(vIds(k)).pos(2);
    end

    faceC = hexResourceColor(hex.resourceType);
    patch(ax, xs, ys, faceC, ...
        'EdgeColor', [0.22 0.16 0.08], ...
        'LineWidth', 2.2);

    cx = hex.center(1);
    cy = hex.center(2);

    % Resource name label.
    text(ax, cx, cy - 0.30, hex.resourceType, ...
        'HorizontalAlignment', 'center', ...
        'FontSize',   7, ...
        'FontWeight', 'bold', ...
        'Color',      [0.10 0.08 0.04]);

    % Dice number token.
    if hex.diceNumber ~= 7
        numColor = [0.08 0.08 0.08];
        if hex.diceNumber == 6 || hex.diceNumber == 8
            numColor = [0.78 0.05 0.05]; % red highlight for high-prob numbers
        end

        % White circular token background.
        theta  = linspace(0, 2*pi, 32);
        txs    = cx + 0.32 * cos(theta);
        tys    = cy + 0.10 + 0.32 * sin(theta);
        patch(ax, txs, tys, [0.96 0.93 0.84], ...
            'EdgeColor', [0.55 0.45 0.30], 'LineWidth', 1.2);

        % Number text.
        text(ax, cx, cy + 0.14, num2str(hex.diceNumber), ...
            'HorizontalAlignment', 'center', ...
            'FontSize',   13, ...
            'FontWeight', 'bold', ...
            'Color',      numColor);

        % Probability pips below the number.
        nPips      = hexDotCount(hex.diceNumber);
        pipSpacing = 0.11;
        startPipX  = cx - (nPips - 1) * pipSpacing / 2;
        for d = 1:nPips
            px = startPipX + (d - 1) * pipSpacing;
            py = cy - 0.11;
            patch(ax, px + 0.035*cos(theta), py + 0.035*sin(theta), numColor, ...
                'EdgeColor', 'none');
        end
    end
end

% --- Vertex ID labels (small, so live player can identify vertices) ---
for v = 1:numel(board.vertices)
    pos = board.vertices(v).pos;
    if board.vertices(v).owner == 0
        text(ax, pos(1), pos(2), num2str(v), ...
            'HorizontalAlignment', 'center', ...
            'FontSize',    5.5, ...
            'Color',       [0.65 0.68 0.78], ...
            'FontAngle',   'italic');
    end
end

% --- Settlement markers ---
for v = 1:numel(board.vertices)
    owner = board.vertices(v).owner;
    if owner ~= 0
        pos = board.vertices(v).pos;
        pc  = playerDisplayColor(owner);

        % Outer ring.
        plot(ax, pos(1), pos(2), 's', ...
            'MarkerSize',      16, ...
            'MarkerFaceColor', pc, ...
            'MarkerEdgeColor', [0.95 0.95 0.95], ...
            'LineWidth',       1.8);

        % Player number label.
        text(ax, pos(1), pos(2), num2str(owner), ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment',   'middle', ...
            'FontSize',   7, ...
            'FontWeight', 'bold', ...
            'Color',      'w');
    end
end

title(ax, 'Catan Board', ...
    'Color',    [0.90 0.92 0.95], ...
    'FontSize', 13, ...
    'FontWeight', 'bold');
end

% -----------------------------------------------------------------
%  Info panel renderer
% -----------------------------------------------------------------

function drawInfoPanel(ax, state, config, playerNames, currentPlayerId, actionStr, rollNum)
%DRAWINFOPANEL  Renders player stats, resources, turn info, and legend.

cla(ax);
axis(ax, 'off');
set(ax, 'Color', [0.08 0.10 0.16]);
hold(ax, 'on');
xlim(ax, [0 1]);
ylim(ax, [0 1]);

P = numel(state.players);

% --- Title ---
text(ax, 0.50, 0.985, 'CATAN', ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment',   'top', ...
    'FontSize',   20, ...
    'FontWeight', 'bold', ...
    'Color',      [0.95 0.80 0.18]);

% --- Turn / roll info ---
if rollNum > 0
    rollStr = sprintf('Turn %d   |   Roll: %d', state.turnIndex, rollNum);
else
    rollStr = sprintf('Initial Placement');
end
text(ax, 0.50, 0.935, rollStr, ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment',   'top', ...
    'FontSize', 10, ...
    'Color',    [0.78 0.84 0.92]);

% --- Last action ---
if ~isempty(actionStr)
    text(ax, 0.50, 0.895, actionStr, ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment',   'top', ...
        'FontSize',    8.5, ...
        'Color',       [0.68 0.82 0.68], ...
        'Interpreter', 'none');
end

% --- Player panels ---
panelTop    = 0.855;
panelBottom = 0.30;
totalH      = panelTop - panelBottom;
panelH      = totalH / P;

for p = 1:P
    yTop = panelTop - (p - 1) * panelH;
    yBot = yTop - panelH + 0.010;
    pc   = playerDisplayColor(p);

    % Panel background.
    if p == currentPlayerId
        bgColor   = [0.17 0.22 0.34];
        edgeColor = pc;
        edgeW     = 2.2;
    else
        bgColor   = [0.12 0.14 0.20];
        edgeColor = [0.28 0.30 0.40];
        edgeW     = 1.0;
    end
    patch(ax, [0.03 0.97 0.97 0.03], [yBot yBot yTop-0.008 yTop-0.008], ...
        bgColor, 'EdgeColor', edgeColor, 'LineWidth', edgeW, 'FaceAlpha', 1.0);

    % Colored player indicator bar (left edge).
    patch(ax, [0.03 0.065 0.065 0.03], [yBot yBot yTop-0.008 yTop-0.008], ...
        pc, 'EdgeColor', 'none');

    % Player name + type.
    nameStr = sprintf('Player %d  —  %s', p, playerNames{p});
    if p == currentPlayerId
        nameStr = [nameStr '  (active)']; %#ok<AGROW>
    end
    text(ax, 0.09, yTop - 0.018, nameStr, ...
        'VerticalAlignment', 'top', ...
        'FontSize',   10, ...
        'FontWeight', 'bold', ...
        'Color',      pc);

    % Victory points — large display.
    text(ax, 0.88, yTop - 0.012, sprintf('%d VP', state.players(p).victoryPoints), ...
        'HorizontalAlignment', 'right', ...
        'VerticalAlignment',   'top', ...
        'FontSize',   13, ...
        'FontWeight', 'bold', ...
        'Color',      [0.95 0.90 0.65]);

    % Settlement count.
    text(ax, 0.09, yTop - 0.018 - 0.048, ...
        sprintf('Settlements: %d', state.players(p).settlementCount), ...
        'VerticalAlignment', 'top', ...
        'FontSize', 8.5, ...
        'Color',    [0.82 0.86 0.90]);

    % Resources row.
    res        = state.players(p).resources;
    rNames     = config.resourceNames;
    shortNames = {'Wd', 'Bk', 'Sh', 'Wh', 'Or'};
    resX       = 0.09;
    resY       = yTop - 0.018 - 0.095;
    boxW       = 0.155;
    boxH       = panelH * 0.30;

    for ri = 1:numel(rNames)
        bx = resX + (ri - 1) * boxW;
        % Colored resource mini-tile.
        patch(ax, bx + [0 boxW-0.01 boxW-0.01 0], resY + [-boxH -boxH 0 0], ...
            hexResourceColor(rNames{ri}), ...
            'EdgeColor', [0.20 0.18 0.15], 'LineWidth', 0.8);
        % Short name.
        text(ax, bx + (boxW-0.01)/2, resY - 0.002, shortNames{ri}, ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment',   'top', ...
            'FontSize', 6.5, 'Color', [0.12 0.10 0.08], 'FontWeight', 'bold');
        % Count.
        text(ax, bx + (boxW-0.01)/2, resY - boxH/2 - 0.002, num2str(res(ri)), ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment',   'middle', ...
            'FontSize', 10, 'FontWeight', 'bold', 'Color', [0.05 0.05 0.05]);
    end
end

% --- Win-condition bar ---
text(ax, 0.50, panelBottom - 0.012, ...
    sprintf('First to %d settlements wins  |  Max %d turns', ...
    config.winSettlements, config.maxTurns), ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment',   'top', ...
    'FontSize', 8, ...
    'Color',    [0.50 0.54 0.62]);

% --- Resource legend ---
legendTop = panelBottom - 0.065;
text(ax, 0.50, legendTop, 'Resource Legend', ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment',   'top', ...
    'FontSize',   8.5, ...
    'FontWeight', 'bold', ...
    'Color',      [0.72 0.74 0.82]);

rTypes  = {'wood', 'brick', 'sheep', 'wheat', 'ore', 'desert'};
cols    = 3;
lBoxW   = 0.24;
lBoxH   = 0.040;
lStartX = 0.07;
lStartY = legendTop - 0.035;

for ri = 1:numel(rTypes)
    row = floor((ri - 1) / cols);
    col = mod(ri - 1, cols);
    bx  = lStartX + col * (lBoxW + 0.04);
    by  = lStartY - row * (lBoxH + 0.014);

    patch(ax, bx + [0 lBoxW lBoxW 0], by + [-lBoxH -lBoxH 0 0], ...
        hexResourceColor(rTypes{ri}), ...
        'EdgeColor', [0.30 0.28 0.22], 'LineWidth', 1.0);
    text(ax, bx + lBoxW + 0.015, by - lBoxH/2, rTypes{ri}, ...
        'VerticalAlignment', 'middle', ...
        'FontSize', 7.5, ...
        'Color',    [0.78 0.80 0.88]);
end
end

%% ------------------------- Color Helpers -------------------------

function c = hexResourceColor(rType)
%HEXRESOURCECOLOR  Face color for a hex tile based on its resource type.
switch lower(rType)
    case 'wood',   c = [0.18 0.50 0.18];
    case 'brick',  c = [0.74 0.28 0.08];
    case 'sheep',  c = [0.62 0.88 0.32];
    case 'wheat',  c = [0.94 0.82 0.12];
    case 'ore',    c = [0.52 0.54 0.60];
    case 'desert', c = [0.90 0.82 0.54];
    otherwise,     c = [0.50 0.50 0.50];
end
end

function c = playerDisplayColor(playerId)
%PLAYERDISPLAYCOLOR  Unique display color per player index (cycles for >4 players).
colors = [
    0.92 0.22 0.22;   % P1 red
    0.25 0.52 0.96;   % P2 blue
    0.96 0.66 0.10;   % P3 orange
    0.24 0.82 0.36;   % P4 green
];
if playerId == 0
    c = [0.50 0.50 0.50];
else
    c = colors(mod(playerId - 1, size(colors, 1)) + 1, :);
end
end

function n = hexDotCount(diceNum)
%HEXDOTCOUNT  Number of probability pips shown on a dice token (mirrors Catan standard).
dotMap = [1 2 3 4 5 0 5 4 3 2 1]; % indices 1..11 correspond to rolls 2..12
if diceNum < 2 || diceNum > 12
    n = 0;
else
    n = dotMap(diceNum - 1);
end
end

%% ------------------------- Board Generation -------------------------

function board = createCatanBoard()
%CREATECATANBOARD  Full-size randomized Catan board (19 hexes, 54 vertices).

axial    = axialCoordsRadius2();
numHexes = size(axial, 1);
sizeHex  = 1.0;
angles   = deg2rad(30 + (0:5) * 60);

resourceBag = [ ...
    repmat({'wood'},  1, 4), repmat({'brick'}, 1, 3), ...
    repmat({'sheep'}, 1, 4), repmat({'wheat'}, 1, 4), ...
    repmat({'ore'},   1, 3), {'desert'}];
resourceBag = resourceBag(randperm(numel(resourceBag)));

numberBag = [2 12, 3 3, 4 4, 5 5, 6 6, 8 8, 9 9, 10 10, 11 11];
numberBag = numberBag(randperm(numel(numberBag)));

diceNumbers = zeros(1, numHexes);
ndx = 1;
for h = 1:numHexes
    if strcmp(resourceBag{h}, 'desert')
        diceNumbers(h) = 7;
    else
        diceNumbers(h) = numberBag(ndx);
        ndx = ndx + 1;
    end
end

vertexMap      = containers.Map('KeyType', 'char', 'ValueType', 'int32');
vertexPos      = zeros(0, 2);
vertexAdjHexes = {};
hexVertexIds   = zeros(numHexes, 6);

for h = 1:numHexes
    center = axialToCartesian(axial(h, :), sizeHex);
    for k = 1:6
        pos = center + sizeHex * [cos(angles(k)), sin(angles(k))];
        key = vertexKey(pos);
        if ~isKey(vertexMap, key)
            newId = size(vertexPos, 1) + 1;
            vertexMap(key)        = newId;
            vertexPos(newId, :)   = pos;
            vertexAdjHexes{newId} = h; %#ok<AGROW>
            vId = newId;
        else
            vId = vertexMap(key);
            vertexAdjHexes{vId} = unique([vertexAdjHexes{vId}, h]);
        end
        hexVertexIds(h, k) = vId;
    end
end

numVertices = size(vertexPos, 1);
adjMat = false(numVertices);
for h = 1:numHexes
    ids = hexVertexIds(h, :);
    for k = 1:6
        a = ids(k);
        b = ids(mod(k, 6) + 1);
        adjMat(a, b) = true;
        adjMat(b, a) = true;
    end
end

vertices = repmat(struct('owner', 0, 'adjHexIds', [], 'adjVertexIds', [], 'pos', [0,0]), ...
    1, numVertices);
for v = 1:numVertices
    vertices(v).owner        = 0;
    vertices(v).adjHexIds    = sort(vertexAdjHexes{v});
    vertices(v).adjVertexIds = find(adjMat(v, :));
    vertices(v).pos          = vertexPos(v, :);
end

hexes = repmat(struct('resourceType', '', 'diceNumber', 0, 'vertexIds', zeros(1,6), 'center', [0,0]), ...
    1, numHexes);
for h = 1:numHexes
    hexes(h).resourceType = resourceBag{h};
    hexes(h).diceNumber   = diceNumbers(h);
    hexes(h).vertexIds    = hexVertexIds(h, :);
    hexes(h).center       = axialToCartesian(axial(h, :), sizeHex);
end

board = struct('hexes', hexes, 'vertices', vertices);
end

function axial = axialCoordsRadius2()
%AXIALCOORDSRADIUS2  19 axial (q,r) coordinates for a radius-2 hex grid.
R      = 2;
coords = zeros(0, 2);
for q = -R:R
    for r = -R:R
        s = -q - r;
        if max([abs(q), abs(r), abs(s)]) <= R
            coords(end + 1, :) = [q, r]; %#ok<AGROW>
        end
    end
end
axial = coords;
end

function xy = axialToCartesian(qr, scale)
%AXIALTOCARTESIAN  Axial hex coord to 2D XY (pointy-top layout).
q  = qr(1);
r  = qr(2);
xy = scale * [sqrt(3) * (q + r / 2), 1.5 * r];
end

function key = vertexKey(pos)
%VERTEXKEY  Stable map key from a vertex position (rounded to 6 decimal places).
key = sprintf('%.6f_%.6f', round(pos(1), 6), round(pos(2), 6));
end

%% ========================= TOURNAMENT =========================

function results = runTournament(agentNames, N, config)
%RUNTOURNAMENT  Round-robin 2-player tournament across a set of agents.
%
% Usage (from MATLAB command window):
%   results = catan_core('runTournament', {'random','heuristic','mcts'}, 20)
%   results = catan_core('runTournament', {'random','heuristic'}, 50, myConfig)
%
% agentNames : cell array of agent type strings
%              ('random', 'heuristic', 'monte_carlo', 'mcts')
% N          : number of games per ordered matchup (total = 2*N per unordered pair)
% config     : (optional) base config struct — showViz/pauseAfterMove/verbose
%              are forced to false/false/false regardless of what you pass
%
% Returns a struct with:
%   results.names          — agent name list
%   results.winRateMatrix  — winRateMatrix(i,j) = P1-win-rate of agent i vs agent j
%   results.overallWinRate — overall win rate per agent (P1 + P2 combined)
%   results.winsAsP1       — total wins as first player per agent
%   results.winsAsP2       — total wins as second player per agent
%   results.gamesPerAgent  — total games each agent participated in

if nargin < 3 || isempty(config)
    config = defaultConfig();
end

% Tournament always runs silently and without visualization.
config.showViz        = false;
config.pauseAfterMove = false;
config.verbose        = false;

numAgents = numel(agentNames);
agentFns  = cell(1, numAgents);
for i = 1:numAgents
    agentFns{i} = resolveAgentFn(agentNames{i});
end

% wins(i,j)   = games P1=agent_i won when matched against P2=agent_j
% vpSumP1(i,j) = total VP earned by P1 (agent i) in those games
wins    = zeros(numAgents, numAgents);
vpSumP1 = zeros(numAgents, numAgents);

fprintf('\n========================================\n');
fprintf('  TOURNAMENT  (%d games per matchup)\n', N);
fprintf('========================================\n');

baseRngSeed = config.rngSeed;
gameNum     = 0;

for i = 1:numAgents
    for j = 1:numAgents
        if i == j, continue; end

        fprintf('  %s (P1) vs %s (P2) ... ', agentNames{i}, agentNames{j});

        for g = 1:N
            gameNum     = gameNum + 1;
            cfg         = config;
            cfg.rngSeed = baseRngSeed + gameNum;

            h = simulateGame( ...
                {agentFns{i}, agentFns{j}}, cfg, ...
                {agentNames{i}, agentNames{j}});

            if h.finalState.winnerId == 1        % P1 (agent i) won
                wins(i, j) = wins(i, j) + 1;
            end
            vpSumP1(i, j) = vpSumP1(i, j) + h.finalState.players(1).victoryPoints;
        end

        fprintf('%d / %d wins for P1\n', wins(i, j), N);
    end
end

% ---- Compute statistics ----

winRateMatrix = wins ./ N;   % P1 win-rate for each ordered pair (i,j)

% Overall win rate: wins as P1 + wins as P2 across all matchups.
winsAsP1 = zeros(1, numAgents);
winsAsP2 = zeros(1, numAgents);
for i = 1:numAgents
    for j = 1:numAgents
        if i == j, continue; end
        winsAsP1(i) = winsAsP1(i) + wins(i, j);
        % In game (j, i), agent i is P2. Wins for P2 = N - wins for P1.
        winsAsP2(i) = winsAsP2(i) + (N - wins(j, i));
    end
end
gamesPerAgent  = (numAgents - 1) * 2 * N;
overallWinRate = (winsAsP1 + winsAsP2) / gamesPerAgent;

% ---- Print results table ----

namePad = max(cellfun(@numel, agentNames)) + 2;
colW    = 12;

fprintf('\n--- P1 Win-Rate Matrix (row = P1 agent, col = P2 opponent) ---\n');
fprintf('%*s', namePad, '');
for j = 1:numAgents
    fprintf('%-*s', colW, agentNames{j});
end
fprintf('\n');
for i = 1:numAgents
    fprintf('%-*s', namePad, agentNames{i});
    for j = 1:numAgents
        if i == j
            fprintf('%-*s', colW, '  --');
        else
            fprintf('%-*s', colW, sprintf('  %.3f', winRateMatrix(i, j)));
        end
    end
    fprintf('\n');
end

fprintf('\n--- Overall Win Rate (P1 + P2 combined) ---\n');
for i = 1:numAgents
    totalW = winsAsP1(i) + winsAsP2(i);
    fprintf('  %-15s : %.3f  (%d / %d games)\n', ...
        agentNames{i}, overallWinRate(i), totalW, gamesPerAgent);
end
fprintf('========================================\n\n');

% ---- Plot ----

fig = figure('Name', 'Tournament Results', 'NumberTitle', 'off', ...
    'Color', [0.10 0.13 0.20], 'Position', [80 80 980 460]);

% Left panel: overall win-rate bar chart.
ax1 = subplot(1, 2, 1, 'Parent', fig);
b   = bar(ax1, overallWinRate * 100);
b.FaceColor = 'flat';
for k = 1:numAgents
    b.CData(k, :) = playerDisplayColor(k);
end
set(ax1, 'XTick', 1:numAgents, 'XTickLabel', agentNames, ...
    'Color', [0.12 0.15 0.22], ...
    'XColor', [0.80 0.85 0.90], 'YColor', [0.80 0.85 0.90], ...
    'GridColor', [0.30 0.35 0.45]);
title(ax1, 'Overall Win Rate (%)', ...
    'Color', [0.95 0.92 0.65], 'FontSize', 12, 'FontWeight', 'bold');
ylabel(ax1, 'Win %', 'Color', [0.80 0.85 0.90]);
ylim(ax1, [0 100]);
grid(ax1, 'on');

% Right panel: P1-win-rate heat map.
ax2 = subplot(1, 2, 2, 'Parent', fig);
displayMat = winRateMatrix;
for k = 1:numAgents
    displayMat(k, k) = NaN;
end
imagesc(ax2, displayMat, [0 1]);
colormap(ax2, 'cool');
colorbar(ax2);
set(ax2, 'XTick', 1:numAgents, 'YTick', 1:numAgents, ...
    'XTickLabel', agentNames, 'YTickLabel', agentNames, ...
    'XColor', [0.80 0.85 0.90], 'YColor', [0.80 0.85 0.90]);
xlabel(ax2, 'P2 (opponent)',    'Color', [0.80 0.85 0.90]);
ylabel(ax2, 'P1 (row agent)',   'Color', [0.80 0.85 0.90]);
title(ax2, 'P1 Win Rate vs Opponent', ...
    'Color', [0.95 0.92 0.65], 'FontSize', 12, 'FontWeight', 'bold');
for i = 1:numAgents
    for j = 1:numAgents
        if i ~= j
            text(ax2, j, i, sprintf('%.2f', winRateMatrix(i, j)), ...
                'HorizontalAlignment', 'center', ...
                'Color', 'w', 'FontWeight', 'bold', 'FontSize', 10);
        end
    end
end
drawnow;

% ---- Pack results ----

results.names          = agentNames;
results.winRateMatrix  = winRateMatrix;
results.overallWinRate = overallWinRate;
results.winsAsP1       = winsAsP1;
results.winsAsP2       = winsAsP2;
results.gamesPerAgent  = gamesPerAgent;
results.vpSumP1        = vpSumP1;
end

function fn = resolveAgentFn(name)
%RESOLVEAGENTFN  Map an agent name string to its function handle.
switch lower(name)
    case 'random',       fn = @agent_random;
    case 'heuristic',    fn = @agent_heuristic;
    case 'monte_carlo',  fn = @agent_montecarlo;
    case 'mcts',         fn = @agent_mcts;
    otherwise
        error('Unknown agent "%s". Choose from: random, heuristic, monte_carlo, mcts.', name);
end
end
