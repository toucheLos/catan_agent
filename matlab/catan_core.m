function varargout = catan_core(command, varargin)
%            robber, ports, maritime trading (single-file MATLAB module).
%
% Start a game:
%   catan_core
%
% Command API:
%   config  = catan_core('defaultConfig')
%   history = catan_core('simulateGame', agentFns, config)
%   legal   = catan_core('enumerateLegalActions', state, playerId, config)
%   state   = catan_core('applyAction', state, playerId, action, config)
%   [done,w]= catan_core('checkTerminal', state, config)
%   state   = catan_core('distributeResources', state, roll, config)
%   roll    = catan_core('rollDice')
%   action  = catan_core('makeAction', type, vertexId, edgeId, hexId, targetPlayer, resourceType, resource2)
%   tf      = catan_core('isLegalAction', action, legalActions)
%   p       = catan_core('diceProbability', n)
%   vp      = catan_core('computeVP', state, playerId)
%   state   = catan_core('autoRobber', state, playerId, config)
%   state   = catan_core('advanceDevCards', state, playerId)

    if nargin == 0
        runGame();
        return;
    end

    switch lower(command)
        case 'defaultconfig',            varargout{1} = defaultConfig();
        case 'simulategame',             varargout{1} = simulateGame(varargin{:});
        case 'enumeratelegalactions',    varargout{1} = enumerateLegalActions(varargin{:});
        case 'applyaction',              varargout{1} = applyAction(varargin{:});
        case 'checkterminal',            [varargout{1},varargout{2}] = checkTerminal(varargin{:});
        case 'distributeresources',      varargout{1} = distributeResources(varargin{:});
        case 'rolldice',                 varargout{1} = rollDice();
        case 'makeaction',               varargout{1} = makeAction(varargin{:});
        case 'islegalaction',            varargout{1} = isLegalAction(varargin{:});
        case 'diceprobability',          varargout{1} = diceProbability(varargin{1});
        case 'computevp',                varargout{1} = computeVP(varargin{:});
        case 'autorobber',               varargout{1} = autoRobber(varargin{:});
        case 'advancedevcards',          varargout{1} = advanceDevCards(varargin{:});
        case 'longestroadlen',           varargout{1} = computeLongestRoadLen(varargin{:});
        case 'traderates',               varargout{1} = getTradeRates(varargin{:});
        case 'canbuildroad',             varargout{1} = canBuildRoadAtEdge(varargin{:});
        case 'enumeraterobberactions',   varargout{1} = enumerateRobberActions(varargin{:});
        case 'rungame',                  runGame();
        otherwise
            error('Unknown catan_core command: %s', command);
    end
end

%% ENTRY POINT

function runGame()
%RUNGAME  Main entry point. Edit PARAMS below, then run: catan_core
%
% Player types: 'random' | 'heuristic' | 'monte_carlo' | 'mcts' | 'live'

PARAMS.players        = {'random', 'heuristic', 'monte_carlo', 'mcts'};
PARAMS.pauseAfterMove = true;
PARAMS.rngSeed        = 0;  % 0 = random board each run; set a fixed int for reproducibility
PARAMS.winVP          = 10;
PARAMS.maxTurns       = 300;
PARAMS.showViz        = true;
PARAMS.mc.rolloutCount  = 15;
PARAMS.mc.rolloutHorizon  = 15;
PARAMS.mc.selfRolloutPolicy = 'heuristic';
PARAMS.mc.opponentRolloutPolicy = 'random';

config               = defaultConfig();
config.rngSeed       = PARAMS.rngSeed;
config.winVP         = PARAMS.winVP;
config.maxTurns      = PARAMS.maxTurns;
config.pauseAfterMove = PARAMS.pauseAfterMove;
config.showViz       = PARAMS.showViz;
config.rolloutCount  = PARAMS.mc.rolloutCount;
config.rolloutHorizon = PARAMS.mc.rolloutHorizon;
config.mc            = PARAMS.mc;

numPlayers = numel(PARAMS.players);
agentFns   = cell(1, numPlayers);
for i = 1:numPlayers
    agentFns{i} = resolveAgentFn(PARAMS.players{i});
end

fprintf('\n========================================\n');
fprintf('         CATAN SIMULATION\n');
fprintf('========================================\n');
for i = 1:numPlayers
    fprintf('  Player %d: %s\n', i, PARAMS.players{i});
end
fprintf('  Win at:    %d VP\n', config.winVP);
fprintf('  Max turns: %d\n', config.maxTurns);
fprintf('========================================\n\n');

history = simulateGame(agentFns, config, PARAMS.players);

fprintf('\n========================================\n');
fprintf('              GAME OVER\n');
fprintf('========================================\n');
fs = history.finalState;
if fs.winnerId ~= 0
    wId = fs.winnerId;
    fprintf('  Winner: Player %d (%s) with %d VP!\n', ...
        wId, PARAMS.players{wId}, computeVP(fs, wId));
else
    fprintf('  No winner — max turns reached.\n');
end
fprintf('  Total turns: %d\n', fs.turnIndex);
fprintf('  Final standings:\n');
for p = 1:numPlayers
    vp = computeVP(fs, p);
    fprintf('    P%d (%s): %d VP  (S:%d C:%d R:%d)\n', ...
        p, PARAMS.players{p}, vp, ...
        fs.players(p).settlementCount, fs.players(p).cityCount, fs.players(p).roadCount);
end
fprintf('========================================\n');
end

%% ========================= CONFIGURATION =========================

function config = defaultConfig()
config.numPlayers             = 2;
config.maxTurns               = 300;
config.winVP                  = 10;
config.resourceNames          = {'wood','brick','sheep','wheat','ore'};
% Build costs as resource vectors [wood brick sheep wheat ore]
config.buildCosts.settlement  = [1 1 1 1 0];
config.buildCosts.road        = [1 1 0 0 0];
config.buildCosts.city        = [0 0 0 2 3];
config.buildCosts.devCard     = [0 0 1 1 1];
config.initialResources       = [0 0 0 0 0];
config.initialFreeSettlements = 2;
config.enforceDistanceRule    = true;
config.rngSeed                = 0;  % 0 = random; fixed int = reproducible
config.pauseAfterMove         = false;
config.showViz                = true;
config.rolloutCount           = 50;
config.rolloutHorizon         = 15;
config.mc.selfRolloutPolicy     = 'random';
config.mc.opponentRolloutPolicy = 'random';
config.verbose                = true;
config.allowTrade             = true;
config.heuristic.wExpectedProduction = 3.0;
config.heuristic.wResourceNeed       = 1.5;
config.heuristic.wDiversity          = 1.0;
config.heuristic.wBlocking           = 0.2;
config.heuristic.wRoad               = 1.8;
config.heuristic.wCity               = 2.5;
config.mcts.C                 = sqrt(2);
config.mcts.totalBudget       = 300;
% depth = rolloutHorizon means all simulated turns use the guided policy — maximizes signal quality at the cost of slightly slower rollouts.
config.mcts.depth             = config.rolloutHorizon;
end

%% ========================= GAME LOOP =========================

function history = simulateGame(agentFns, config, playerNames)
if nargin < 3 || isempty(playerNames)
    playerNames = arrayfun(@(p) sprintf('P%d',p), 1:numel(agentFns), 'UniformOutput', false);
end
if nargin < 2 || isempty(config)
    config = defaultConfig();
end
config.numPlayers = numel(agentFns);
doPause   = isfield(config,'pauseAfterMove') && config.pauseAfterMove;
useViz    = isfield(config,'showViz') && config.showViz;
doVerbose = ~isfield(config,'verbose') || config.verbose;

state = initGame(config);

fig = [];
if useViz
    fig = initGameFig(state, config, playerNames);
end

state = initialPlacement(state, agentFns, config, playerNames, doPause, fig);

history       = struct();
history.actions = struct('turn',{},'player',{},'roll',{},'type',{},...
    'vertexId',{},'edgeId',{},'hexId',{},'targetPlayer',{},...
    'resourceType',{},'resource2',{},'vp',{});
history.logs  = {};

while ~state.isTerminal

    playerId = state.currentPlayer;

    % Agent inspection hook
    if isfield(config,'inspectTurn') && ~isempty(config.inspectTurn) && state.turnIndex == config.inspectTurn
        inspect_agents(state, playerId, config);
        input('  [Inspector: Press Enter to continue]', 's');
    end

    % Transfer new dev cards to playable at start of player's turn
    state = advanceDevCards(state, playerId);

    % Roll
    state.lastRoll = rollDice();
    roll           = state.lastRoll;

    if doVerbose
        fprintf('----------------------------------------\n');
        fprintf('Turn %d | Player %d (%s) | Roll: %d\n', ...
            state.turnIndex, playerId, playerNames{playerId}, roll);
        printPlayerResources(state, playerId, config);
    end
    history.logs{end+1} = sprintf('Turn %d | P%d rolled %d', ...
        state.turnIndex, playerId, roll);

    % ---- Robber phase (roll == 7) ----
    if roll == 7
        % Discard
        for p = 1:config.numPlayers
            if sum(state.players(p).resources) > 7
                if strcmp(playerNames{p}, 'live')
                    state = liveDiscard(state, p, config);
                else
                    state = autoDiscard(state, p, config);
                end
            end
        end
        % Move robber
        robberLegal = enumerateRobberActions(state, playerId, config);
        if useViz && ishandle(fig) && strcmp(playerNames{playerId},'live')
            highlightRobberActions(fig, robberLegal, state);
        end
        rAction = agentFns{playerId}(state, robberLegal, playerId, config);
        if ~isLegalAction(rAction, robberLegal)
            rAction = robberLegal(1);
        end
        state = applyAction(state, playerId, rAction, config);
        logLine = formatActionLog(playerId, playerNames{playerId}, rAction, state, config);
        if doVerbose, fprintf('%s\n', logLine); end
        history.logs{end+1} = logLine;
        history.actions(end+1) = makeHistoryEntry(state, playerId, roll, rAction);
        if useViz && ishandle(fig)
            updateGameFig(fig, state, config, playerNames, playerId, logLine, roll);
        end
        [done,wId] = checkTerminal(state, config);
        state.isTerminal = done; state.winnerId = wId;
        if state.isTerminal, break; end
    else
        state = distributeResources(state, roll, config);
    end

    % ---- Action phase ----
    state.devCardPlayedThisTurn = false;

    actionCap = 40;
    for actionNum = 1:actionCap
        if state.isTerminal, break; end

        legalActions = enumerateLegalActions(state, playerId, config);

        if useViz && ishandle(fig) && strcmp(playerNames{playerId},'live')
            highlightLegalActions(fig, legalActions, state);
        end

        action = agentFns{playerId}(state, legalActions, playerId, config);
        if ~isLegalAction(action, legalActions)
            action = makeAction('pass', 0);
        end

        % End turn on pass (when no free roads pending)
        if strcmp(action.type,'pass') && state.freeRoads == 0
            break;
        end

        state = applyAction(state, playerId, action, config);

        logLine = formatActionLog(playerId, playerNames{playerId}, action, state, config);
        if doVerbose && ~strcmp(action.type,'pass')
            fprintf('%s\n', logLine);
        end
        history.logs{end+1}   = logLine;
        history.actions(end+1) = makeHistoryEntry(state, playerId, roll, action);

        if useViz && ishandle(fig)
            updateGameFig(fig, state, config, playerNames, playerId, logLine, roll);
        end

        [done,wId] = checkTerminal(state, config);
        state.isTerminal = done; state.winnerId = wId;
        if state.isTerminal, break; end

        if doPause && ~strcmp(playerNames{playerId},'live') && ~strcmp(action.type,'pass')
            input('  [Press Enter to continue]','s');
        end
    end

    state.freeRoads = 0; % safety reset

    if state.isTerminal, break; end

    state.currentPlayer = mod(playerId, config.numPlayers) + 1;
    state.turnIndex     = state.turnIndex + 1;

    [done,wId] = checkTerminal(state, config);
    state.isTerminal = done; state.winnerId = wId;
end

history.finalState = state;
end

%% ========================= INITIALIZATION =========================

function state = initGame(config)
if config.rngSeed == 0
    rng('shuffle');   % truly random seed based on clock
else
    rng(config.rngSeed, 'twister');
end

board      = createCatanBoard();
numP       = config.numPlayers;
numRes     = numel(config.resourceNames);

emptyDevCards = struct('knight',0,'roadBuilding',0,'yearOfPlenty',0,'monopoly',0,'vpCard',0);

players = repmat(struct( ...
    'id',0, 'resources',zeros(1,numRes), ...
    'settlementCount',0, 'cityCount',0, 'roadCount',0, ...
    'victoryPoints',0, 'knightsPlayed',0, ...
    'devCards',emptyDevCards, 'newDevCards',emptyDevCards), 1, numP);

for p = 1:numP
    players(p).id = p;
    players(p).resources = config.initialResources;
    players(p).devCards    = emptyDevCards;
    players(p).newDevCards = emptyDevCards;
end

% Build shuffled dev card deck
deck = [repmat({'knight'},1,14), repmat({'roadBuilding'},1,2), ...
        repmat({'yearOfPlenty'},1,2), repmat({'monopoly'},1,2), ...
        repmat({'vpCard'},1,5)];
deck = deck(randperm(25));

% Find desert hex for initial robber placement
desertHex = 1;
for h = 1:numel(board.hexes)
    if strcmp(board.hexes(h).resourceType,'desert')
        desertHex = h; break;
    end
end

state  = struct();
state.turnIndex           = 1;
state.currentPlayer       = 1;
state.board               = board;
state.players             = players;
state.lastRoll            = 0;
state.isTerminal          = false;
state.winnerId            = 0;
state.robberHex           = desertHex;
state.freeRoads           = 0;
state.devCardPlayedThisTurn = false;
state.devCardDeck         = deck;
state.longestRoadPlayer   = 0;
state.largestArmyPlayer   = 0;
state.placementPhase      = false;
end

%% ========================= INITIAL PLACEMENT =========================

function state = initialPlacement(state, agentFns, config, playerNames, doPause, fig)
P         = config.numPlayers;
K         = config.initialFreeSettlements;   % typically 2
useViz    = ~isempty(fig);
doVerbose = ~isfield(config,'verbose') || config.verbose;

state.placementPhase = true;

if doVerbose
    fprintf('=== Initial Placement (%d settlements + roads each, snake draft) ===\n', K);
end

% Snake draft order: round 1 forward, round 2 backward, etc.
order = [];
for r = 1:K
    if mod(r,2) == 1
        order = [order, 1:P]; %#ok<AGROW>
    else
        order = [order, P:-1:1]; %#ok<AGROW>
    end
end

for idx = 1:numel(order)
    p            = order(idx);
    isSecondRound = (idx > P);

    % --- Place settlement (free) ---
    legal = enumerateLegalActionsFree(state, config);
    if useViz && ishandle(fig) && strcmp(playerNames{p},'live')
        highlightLegalActions(fig, legal, state);
    end
    a = agentFns{p}(state, legal, p, config);
    if ~isLegalAction(a, legal)
        a = (numel(legal) > 1) * legal(2) + (numel(legal)==1) * makeAction('pass',0);
        if numel(legal) > 1, a = legal(2); else, a = makeAction('pass',0); end
    end
    state = applyActionFree(state, p, a, config);
    lastVtx = a.vertexId;

    % In round 2, give starting resources from this settlement
    if isSecondRound && strcmp(a.type,'build_settlement')
        state = giveInitialResources(state, p, lastVtx, config);
    end

    if doVerbose
        fprintf('  P%d placed settlement at v%d\n', p, lastVtx);
    end

    % --- Place initial road (free) adjacent to settlement ---
    if strcmp(a.type,'build_settlement')
        roadLegal = enumerateFreeRoadsAt(state, lastVtx);
        if numel(roadLegal) > 0
            if useViz && ishandle(fig) && strcmp(playerNames{p},'live')
                highlightLegalActions(fig, roadLegal, state);
            end
            ra = agentFns{p}(state, roadLegal, p, config);
            if ~isLegalAction(ra, roadLegal) || strcmp(ra.type,'pass')
                % Force a road — pick first build_road action in the list
                roads = roadLegal(arrayfun(@(x) strcmp(x.type,'build_road'), roadLegal));
                if ~isempty(roads), ra = roads(1); else, ra = roadLegal(1); end
            end
            state = applyFreeRoad(state, p, ra);
            if doVerbose && strcmp(ra.type,'build_road')
                fprintf('  P%d placed road on edge %d\n', p, ra.edgeId);
            end
        end
    end

    if useViz && ishandle(fig)
        statusStr = sprintf('Placement: P%d (%s) @v%d', p, playerNames{p}, lastVtx);
        updateGameFig(fig, state, config, playerNames, p, statusStr, 0);
    end

    if doPause && ~strcmp(playerNames{p},'live')
        input('  [Press Enter to continue]','s');
    end
end

state.placementPhase = false;

if doVerbose
    fprintf('=== Placement complete. Starting game. ===\n\n');
end
end

function legalActions = enumerateLegalActionsFree(state, config)
legalActions = makeAction('pass', 0);
for v = 1:numel(state.board.vertices)
    if state.board.vertices(v).owner ~= 0, continue; end
    if config.enforceDistanceRule
        nbrs = state.board.vertices(v).adjVertexIds;
        if any([state.board.vertices(nbrs).owner] ~= 0), continue; end
    end
    legalActions(end+1) = makeAction('build_settlement', v); %#ok<AGROW>
end
end

function state = applyActionFree(state, playerId, action, config)
if ~strcmp(action.type,'build_settlement'), return; end
v = action.vertexId;
if v < 1 || v > numel(state.board.vertices), return; end
if state.board.vertices(v).owner ~= 0, return; end
if config.enforceDistanceRule
    nbrs = state.board.vertices(v).adjVertexIds;
    if any([state.board.vertices(nbrs).owner] ~= 0), return; end
end
state.board.vertices(v).owner          = playerId;
state.board.vertices(v).isCity         = false;
state.players(playerId).settlementCount = state.players(playerId).settlementCount + 1;
state.players(playerId).victoryPoints   = computeVP(state, playerId);
end

function state = giveInitialResources(state, playerId, vertexId, config)
for h = state.board.vertices(vertexId).adjHexIds
    rType = state.board.hexes(h).resourceType;
    if strcmp(rType,'desert'), continue; end
    rIdx = resourceIndex(rType, config.resourceNames);
    state.players(playerId).resources(rIdx) = state.players(playerId).resources(rIdx) + 1;
end
end

function legal = enumerateFreeRoadsAt(state, vertexId)
% Road placement is mandatory — no pass included so agents can't skip it.
legal = repmat(makeAction('build_road'), 1, 0);
for e = state.board.vertices(vertexId).adjEdgeIds
    if state.board.edges(e).owner ~= 0, continue; end
    a = makeAction('build_road'); a.edgeId = e;
    legal(end+1) = a; %#ok<AGROW>
end
if isempty(legal)
    legal = makeAction('pass', 0);  % only if truly no free edges exist
end
end

function state = applyFreeRoad(state, playerId, action)
if ~strcmp(action.type,'build_road'), return; end
e = action.edgeId;
if e < 1 || e > numel(state.board.edges), return; end
if state.board.edges(e).owner ~= 0, return; end
state.board.edges(e).owner            = playerId;
state.players(playerId).roadCount     = state.players(playerId).roadCount + 1;
end

%% ========================= CORE RULES =========================

function roll = rollDice()
roll = randi(6) + randi(6);
end

function state = distributeResources(state, roll, config)
if roll == 7, return; end  % robber; handled separately
for v = 1:numel(state.board.vertices)
    owner = state.board.vertices(v).owner;
    if owner == 0, continue; end
    mult = 1 + state.board.vertices(v).isCity; % 1 settlement, 2 city
    for h = state.board.vertices(v).adjHexIds
        if state.board.hexes(h).diceNumber ~= roll, continue; end
        if h == state.robberHex, continue; end
        rType = state.board.hexes(h).resourceType;
        if strcmp(rType,'desert'), continue; end
        rIdx = resourceIndex(rType, config.resourceNames);
        state.players(owner).resources(rIdx) = state.players(owner).resources(rIdx) + mult;
    end
end
end

% -----------------------------------------------------------------
%  Legal action enumeration
% -----------------------------------------------------------------

function legalActions = enumerateLegalActions(state, playerId, config)
legalActions = makeAction('pass', 0);
player = state.players(playerId);

% When free roads are pending (road-building card), only offer road building
if state.freeRoads > 0
    for e = 1:numel(state.board.edges)
        if canBuildRoadAtEdge(state, playerId, e)
            a = makeAction('build_road'); a.edgeId = e;
            legalActions(end+1) = a; %#ok<AGROW>
        end
    end
    return;
end

% Build settlement
if canAfford(player.resources, config.buildCosts.settlement)
    for v = 1:numel(state.board.vertices)
        if isLegalSettlement(state, playerId, v, config)
            legalActions(end+1) = makeAction('build_settlement', v); %#ok<AGROW>
        end
    end
end

% Build road
if canAfford(player.resources, config.buildCosts.road)
    for e = 1:numel(state.board.edges)
        if canBuildRoadAtEdge(state, playerId, e)
            a = makeAction('build_road'); a.edgeId = e;
            legalActions(end+1) = a; %#ok<AGROW>
        end
    end
end

% Build city (upgrade own settlement)
if canAfford(player.resources, config.buildCosts.city)
    for v = 1:numel(state.board.vertices)
        if state.board.vertices(v).owner == playerId && ~state.board.vertices(v).isCity
            legalActions(end+1) = makeAction('build_city', v); %#ok<AGROW>
        end
    end
end

% Buy dev card
if canAfford(player.resources, config.buildCosts.devCard) && ~isempty(state.devCardDeck)
    legalActions(end+1) = makeAction('buy_dev_card'); %#ok<AGROW>
end

% Play dev card (one per turn; not cards bought this same turn)
if ~state.devCardPlayedThisTurn
    dc = player.devCards;

    if dc.knight > 0
        robLegal = enumerateRobberActions(state, playerId, config);
        for i = 1:numel(robLegal)
            a = makeAction('play_knight');
            a.hexId = robLegal(i).hexId;
            a.targetPlayer = robLegal(i).targetPlayer;
            legalActions(end+1) = a; %#ok<AGROW>
        end
    end

    if dc.roadBuilding > 0
        legalActions(end+1) = makeAction('play_road_building'); %#ok<AGROW>
    end

    if dc.yearOfPlenty > 0
        rNames = config.resourceNames;
        for r1 = 1:numel(rNames)
            for r2 = r1:numel(rNames)
                a = makeAction('play_year_of_plenty');
                a.resourceType = rNames{r1}; a.resource2 = rNames{r2};
                legalActions(end+1) = a; %#ok<AGROW>
            end
        end
    end

    if dc.monopoly > 0
        for ri = 1:numel(config.resourceNames)
            a = makeAction('play_monopoly');
            a.resourceType = config.resourceNames{ri};
            legalActions(end+1) = a; %#ok<AGROW>
        end
    end
end

% Maritime trading
if ~isfield(config,'allowTrade') || config.allowTrade
    rates = getTradeRates(state, playerId, config);
    rNames = config.resourceNames;
    for ri = 1:numel(rNames)
        if player.resources(ri) >= rates(ri)
            for rj = 1:numel(rNames)
                if ri == rj, continue; end
                a = makeAction('maritime_trade');
                a.resourceType = rNames{ri}; a.resource2 = rNames{rj};
                legalActions(end+1) = a; %#ok<AGROW>
            end
        end
    end
end
end

% -----------------------------------------------------------------
%  Apply action
% -----------------------------------------------------------------

function state = applyAction(state, playerId, action, config)
switch action.type
    case 'pass'
        % nothing
    case 'build_settlement'
        state = applyBuildSettlement(state, playerId, action, config);
    case 'build_road'
        state = applyBuildRoad(state, playerId, action, config);
    case 'build_city'
        state = applyBuildCity(state, playerId, action, config);
    case 'buy_dev_card'
        state = applyBuyDevCard(state, playerId, config);
    case 'play_road_building'
        state.devCardPlayedThisTurn = true;
        state.players(playerId).devCards.roadBuilding = ...
            state.players(playerId).devCards.roadBuilding - 1;
        state.freeRoads = 2;
    case 'play_year_of_plenty'
        state.devCardPlayedThisTurn = true;
        state.players(playerId).devCards.yearOfPlenty = ...
            state.players(playerId).devCards.yearOfPlenty - 1;
        r1 = resourceIndex(action.resourceType, config.resourceNames);
        r2 = resourceIndex(action.resource2,    config.resourceNames);
        state.players(playerId).resources(r1) = state.players(playerId).resources(r1) + 1;
        state.players(playerId).resources(r2) = state.players(playerId).resources(r2) + 1;
    case 'play_monopoly'
        state.devCardPlayedThisTurn = true;
        state.players(playerId).devCards.monopoly = ...
            state.players(playerId).devCards.monopoly - 1;
        rIdx = resourceIndex(action.resourceType, config.resourceNames);
        for op = 1:numel(state.players)
            if op == playerId, continue; end
            stolen = state.players(op).resources(rIdx);
            state.players(op).resources(rIdx) = 0;
            state.players(playerId).resources(rIdx) = ...
                state.players(playerId).resources(rIdx) + stolen;
        end
    case 'play_knight'
        state.devCardPlayedThisTurn = true;
        state.players(playerId).devCards.knight = ...
            state.players(playerId).devCards.knight - 1;
        state.players(playerId).knightsPlayed = ...
            state.players(playerId).knightsPlayed + 1;
        state = applyMoveRobber(state, playerId, action, config);
        state = updateLargestArmy(state);
    case 'move_robber'
        state = applyMoveRobber(state, playerId, action, config);
    case 'maritime_trade'
        state = applyMaritimeTrade(state, playerId, action, config);
end
state = updateVPs(state);
end

function state = applyBuildSettlement(state, playerId, action, config)
v = action.vertexId;
if v < 1 || v > numel(state.board.vertices), return; end
if state.board.vertices(v).owner ~= 0, return; end
if config.enforceDistanceRule
    nbrs = state.board.vertices(v).adjVertexIds;
    if any([state.board.vertices(nbrs).owner] ~= 0), return; end
end
isFreePlacement = isfield(state,'placementPhase') && state.placementPhase;
if ~isFreePlacement
    if ~canAfford(state.players(playerId).resources, config.buildCosts.settlement), return; end
    state.players(playerId).resources = ...
        state.players(playerId).resources - config.buildCosts.settlement;
end
state.board.vertices(v).owner  = playerId;
state.board.vertices(v).isCity = false;
state.players(playerId).settlementCount = state.players(playerId).settlementCount + 1;
% Building a settlement can affect longest road (may break opponent's road)
state = updateLongestRoad(state);
end

function state = applyBuildRoad(state, playerId, action, config)
e = action.edgeId;
if e < 1 || e > numel(state.board.edges), return; end
if state.board.edges(e).owner ~= 0, return; end
if ~canBuildRoadAtEdge(state, playerId, e), return; end
if state.freeRoads > 0
    state.freeRoads = state.freeRoads - 1;
else
    if ~canAfford(state.players(playerId).resources, config.buildCosts.road), return; end
    state.players(playerId).resources = ...
        state.players(playerId).resources - config.buildCosts.road;
end
state.board.edges(e).owner        = playerId;
state.players(playerId).roadCount = state.players(playerId).roadCount + 1;
state = updateLongestRoad(state);
end

function state = applyBuildCity(state, playerId, action, config)
v = action.vertexId;
if v < 1 || v > numel(state.board.vertices), return; end
if state.board.vertices(v).owner ~= playerId, return; end
if state.board.vertices(v).isCity, return; end
if ~canAfford(state.players(playerId).resources, config.buildCosts.city), return; end
state.players(playerId).resources = ...
    state.players(playerId).resources - config.buildCosts.city;
state.board.vertices(v).isCity = true;
state.players(playerId).settlementCount = state.players(playerId).settlementCount - 1;
state.players(playerId).cityCount       = state.players(playerId).cityCount + 1;
end

function state = applyBuyDevCard(state, playerId, config)
if isempty(state.devCardDeck), return; end
if ~canAfford(state.players(playerId).resources, config.buildCosts.devCard), return; end
state.players(playerId).resources = ...
    state.players(playerId).resources - config.buildCosts.devCard;
cardType = state.devCardDeck{end};
state.devCardDeck(end) = [];
if strcmp(cardType,'vpCard')
    state.players(playerId).devCards.vpCard = ...
        state.players(playerId).devCards.vpCard + 1;
else
    state.players(playerId).newDevCards.(cardType) = ...
        state.players(playerId).newDevCards.(cardType) + 1;
end
end

function state = advanceDevCards(state, playerId)
% Move cards bought last turn into the playable hand
fields = fieldnames(state.players(playerId).newDevCards);
for i = 1:numel(fields)
    f = fields{i};
    state.players(playerId).devCards.(f) = ...
        state.players(playerId).devCards.(f) + state.players(playerId).newDevCards.(f);
    state.players(playerId).newDevCards.(f) = 0;
end
end

function state = applyMaritimeTrade(state, playerId, action, config)
rates    = getTradeRates(state, playerId, config);
giveIdx  = resourceIndex(action.resourceType, config.resourceNames);
recvIdx  = resourceIndex(action.resource2,    config.resourceNames);
if giveIdx == recvIdx, return; end
rate = rates(giveIdx);
if state.players(playerId).resources(giveIdx) < rate, return; end
state.players(playerId).resources(giveIdx) = ...
    state.players(playerId).resources(giveIdx) - rate;
state.players(playerId).resources(recvIdx) = ...
    state.players(playerId).resources(recvIdx) + 1;
end

function [done, winnerId] = checkTerminal(state, config)
done     = false;
winnerId = 0;
winVP    = config.winVP;
for p = 1:numel(state.players)
    if state.players(p).victoryPoints >= winVP
        done     = true;
        winnerId = p;
        return;
    end
end
if state.turnIndex > config.maxTurns
    done = true;
    [~, winnerId] = max([state.players.victoryPoints]);
end
end

%% ========================= ROBBER =========================

function legalActions = enumerateRobberActions(state, playerId, config) %#ok<INUSD>
first = true;
for h = 1:numel(state.board.hexes)
    if h == state.robberHex, continue; end
    playersOnHex = [];
    for vid = state.board.hexes(h).vertexIds
        ow = state.board.vertices(vid).owner;
        if ow ~= 0 && ow ~= playerId && ~ismember(ow, playersOnHex)
            playersOnHex(end+1) = ow; %#ok<AGROW>
        end
    end
    if isempty(playersOnHex)
        a = makeAction('move_robber'); a.hexId = h; a.targetPlayer = 0;
        if first, legalActions = a; first = false;
        else, legalActions(end+1) = a; end %#ok<AGROW>
    else
        for tp = playersOnHex
            a = makeAction('move_robber'); a.hexId = h; a.targetPlayer = tp;
            if first, legalActions = a; first = false;
            else, legalActions(end+1) = a; end %#ok<AGROW>
        end
    end
end
if first
    % Fallback: move to hex 1 (shouldn't normally be needed)
    a = makeAction('move_robber'); a.hexId = 1; a.targetPlayer = 0;
    legalActions = a;
end
end

function state = applyMoveRobber(state, playerId, action, config) %#ok<INUSD>
h = action.hexId;
if h < 1 || h > numel(state.board.hexes), return; end
state.robberHex = h;
tp = action.targetPlayer;
if tp ~= 0 && tp ~= playerId
    res   = state.players(tp).resources;
    total = sum(res);
    if total > 0
        cum  = cumsum(res);
        r    = randi(total);
        rIdx = find(cum >= r, 1);
        state.players(tp).resources(rIdx)         = state.players(tp).resources(rIdx) - 1;
        state.players(playerId).resources(rIdx)   = state.players(playerId).resources(rIdx) + 1;
    end
end
end

function state = autoRobber(state, playerId, config)
%AUTOROBBER  Simplified robber for rollouts: move to highest-impact hex.
legal = enumerateRobberActions(state, playerId, config);
best  = -inf;
pick  = legal(1);
for i = 1:numel(legal)
    a = legal(i);
    if a.hexId == 0, continue; end
    hex  = state.board.hexes(a.hexId);
    prob = diceProbability(hex.diceNumber);
    nOpp = 0;
    for vid = hex.vertexIds
        ow = state.board.vertices(vid).owner;
        if ow ~= 0 && ow ~= playerId, nOpp = nOpp + 1; end
    end
    sc = prob * nOpp;
    if sc > best, best = sc; pick = a; end
end
state = applyMoveRobber(state, playerId, pick, config);
state = updateVPs(state);
end

function state = autoDiscard(state, playerId, config) %#ok<INUSD>
res   = state.players(playerId).resources;
total = sum(res);
if total <= 7, return; end
toDiscard = floor(total / 2);
for d = 1:toDiscard
    [~, idx] = max(res);
    res(idx) = res(idx) - 1;
end
state.players(playerId).resources = res;
end

function state = liveDiscard(state, playerId, config)
res   = state.players(playerId).resources;
total = sum(res);
nDiscard = floor(total / 2);
fprintf('\n  *** Player %d must discard %d cards (has %d) ***\n', playerId, nDiscard, total);
rNames = config.resourceNames;
for d = 1:nDiscard
    fprintf('  Resources: ');
    for i = 1:numel(rNames), fprintf('%s=%d  ', rNames{i}, res(i)); end
    fprintf('\n');
    ok = false;
    while ~ok
        raw = input('  Discard which resource (name)? ','s');
        rIdx = find(strcmp(rNames, strtrim(lower(raw))), 1);
        if ~isempty(rIdx) && res(rIdx) > 0
            res(rIdx) = res(rIdx) - 1;
            ok = true;
        else
            fprintf('  Invalid. Choose from: %s\n', strjoin(rNames(res>0), ', '));
        end
    end
end
state.players(playerId).resources = res;
end

%% ========================= VP / LONGEST ROAD / LARGEST ARMY =========================

function vp = computeVP(state, playerId)
vp = 0;
for v = 1:numel(state.board.vertices)
    if state.board.vertices(v).owner == playerId
        vp = vp + 1 + state.board.vertices(v).isCity; % 1 settle or 2 city
    end
end
if state.longestRoadPlayer == playerId, vp = vp + 2; end
if state.largestArmyPlayer == playerId, vp = vp + 2; end
vp = vp + state.players(playerId).devCards.vpCard;
end

function state = updateVPs(state)
for p = 1:numel(state.players)
    state.players(p).victoryPoints = computeVP(state, p);
end
end

function state = updateLongestRoad(state)
numP = numel(state.players);
lens = zeros(1, numP);
for p = 1:numP
    lens(p) = computeLongestRoadLen(state, p);
end
[maxLen, ~] = max(lens);
cur = state.longestRoadPlayer;
if maxLen < 5
    state.longestRoadPlayer = 0;
    return;
end
if cur ~= 0 && lens(cur) == maxLen
    return; % current holder keeps (tie)
end
if cur == 0
    for p = 1:numP
        if lens(p) == maxLen, state.longestRoadPlayer = p; return; end
    end
else
    if maxLen > lens(cur)
        for p = 1:numP
            if lens(p) == maxLen, state.longestRoadPlayer = p; return; end
        end
    end
end
end

function len = computeLongestRoadLen(state, playerId)
board    = state.board;
if ~isfield(board,'edges') || isempty(board.edges), len = 0; return; end
numEdges = numel(board.edges);
hasPEdge = false;
for e = 1:numEdges
    if board.edges(e).owner == playerId, hasPEdge = true; break; end
end
if ~hasPEdge, len = 0; return; end

allV = [];
for e = 1:numEdges
    if board.edges(e).owner == playerId
        allV = [allV, board.edges(e).vertexIds]; %#ok<AGROW>
    end
end
startVerts = unique(allV);

len      = 0;
usedE    = false(1, numEdges);
for sv = startVerts
    l = dfsRoad(board, playerId, sv, usedE);
    if l > len, len = l; end
end
end

function len = dfsRoad(board, playerId, v, usedEdges)
len = 0;
for e = board.vertices(v).adjEdgeIds
    if board.edges(e).owner ~= playerId, continue; end
    if usedEdges(e), continue; end
    vPair = board.edges(e).vertexIds;
    nv    = vPair(vPair ~= v);
    if isempty(nv), continue; end
    nv    = nv(1);
    nOwner = board.vertices(nv).owner;
    if nOwner ~= 0 && nOwner ~= playerId
        if 1 > len, len = 1; end
    else
        usedEdges(e) = true;
        sl = 1 + dfsRoad(board, playerId, nv, usedEdges);
        usedEdges(e) = false;
        if sl > len, len = sl; end
    end
end
end

function state = updateLargestArmy(state)
numP    = numel(state.players);
knights = zeros(1, numP);
for p = 1:numP, knights(p) = state.players(p).knightsPlayed; end
[maxK, ~] = max(knights);
cur = state.largestArmyPlayer;
if maxK < 3, state.largestArmyPlayer = 0; return; end
if cur ~= 0 && knights(cur) == maxK, return; end
if cur == 0
    for p = 1:numP
        if knights(p) == maxK, state.largestArmyPlayer = p; return; end
    end
else
    if maxK > knights(cur)
        for p = 1:numP
            if knights(p) == maxK, state.largestArmyPlayer = p; return; end
        end
    end
end
end

%% ========================= TRADING =========================

function rates = getTradeRates(state, playerId, config)
rates = 4 * ones(1, numel(config.resourceNames));
for v = 1:numel(state.board.vertices)
    if state.board.vertices(v).owner ~= playerId, continue; end
    port = state.board.vertices(v).portType;
    if strcmp(port,'none'), continue; end
    if strcmp(port,'3to1')
        rates = min(rates, 3);
    else
        % e.g. 'wood2to1' → strip '2to1'
        rName = port(1:end-4);
        rIdx  = find(strcmp(config.resourceNames, rName), 1);
        if ~isempty(rIdx)
            rates(rIdx) = min(rates(rIdx), 2);
        end
    end
end
end

%% ========================= ACTION / STATE HELPERS =========================

function action = makeAction(type, vertexId, edgeId, hexId, targetPlayer, resourceType, resource2)
action.type         = type;
action.vertexId     = 0;
action.edgeId       = 0;
action.hexId        = 0;
action.targetPlayer = 0;
action.resourceType = '';
action.resource2    = '';
if nargin > 1 && ~isempty(vertexId),     action.vertexId     = vertexId;     end
if nargin > 2 && ~isempty(edgeId),       action.edgeId       = edgeId;       end
if nargin > 3 && ~isempty(hexId),        action.hexId        = hexId;        end
if nargin > 4 && ~isempty(targetPlayer), action.targetPlayer = targetPlayer; end
if nargin > 5 && ~isempty(resourceType), action.resourceType = resourceType; end
if nargin > 6 && ~isempty(resource2),    action.resource2    = resource2;    end
end

function tf = isLegalAction(action, legalActions)
tf = false;
for i = 1:numel(legalActions)
    la = legalActions(i);
    if ~strcmp(action.type, la.type), continue; end
    switch action.type
        case 'pass'
            tf = true; return;
        case {'build_settlement','build_city'}
            if action.vertexId == la.vertexId, tf = true; return; end
        case 'build_road'
            if action.edgeId == la.edgeId, tf = true; return; end
        case {'move_robber','play_knight'}
            if action.hexId == la.hexId && action.targetPlayer == la.targetPlayer
                tf = true; return;
            end
        case {'buy_dev_card','play_road_building'}
            tf = true; return;
        case 'play_year_of_plenty'
            if strcmp(action.resourceType, la.resourceType) && strcmp(action.resource2, la.resource2)
                tf = true; return;
            end
        case 'play_monopoly'
            if strcmp(action.resourceType, la.resourceType), tf = true; return; end
        case 'maritime_trade'
            if strcmp(action.resourceType, la.resourceType) && strcmp(action.resource2, la.resource2)
                tf = true; return;
            end
    end
end
end

function tf = isLegalSettlement(state, playerId, v, config)
tf = false;
if state.board.vertices(v).owner ~= 0, return; end
if config.enforceDistanceRule
    nbrs = state.board.vertices(v).adjVertexIds;
    if any([state.board.vertices(nbrs).owner] ~= 0), return; end
end
% Must have road connectivity
for e = state.board.vertices(v).adjEdgeIds
    if state.board.edges(e).owner == playerId, tf = true; return; end
end
end

function tf = canBuildRoadAtEdge(state, playerId, e)
tf = false;
if state.board.edges(e).owner ~= 0, return; end
vPair = state.board.edges(e).vertexIds;
for k = 1:2
    v = vPair(k);
    if isRoadConnectableAt(state, playerId, v, e), tf = true; return; end
end
end

function tf = isRoadConnectableAt(state, playerId, v, excludeEdge)
% Player can connect a road at v if they own a structure there,
% or own an adjacent road (not blocked by an opponent settlement).
if state.board.vertices(v).owner == playerId, tf = true; return; end
if state.board.vertices(v).owner ~= 0 % opponent blocks
    tf = false; return;
end
for e2 = state.board.vertices(v).adjEdgeIds
    if e2 ~= excludeEdge && state.board.edges(e2).owner == playerId
        tf = true; return;
    end
end
tf = false;
end

function p = diceProbability(n)
weights = [1 2 3 4 5 6 5 4 3 2 1];
if n < 2 || n > 12, p = 0;
else, p = weights(n-1) / 36; end
end

function tf = canAfford(resources, cost)
tf = all(resources >= cost);
end

function idx = resourceIndex(resourceType, resourceNames)
idx = find(strcmp(resourceNames, resourceType), 1);
if isempty(idx)
    error('Unknown resource type: %s', resourceType);
end
end

function printPlayerResources(state, playerId, config)
res   = state.players(playerId).resources;
names = config.resourceNames;
parts = cell(1, numel(names));
for i = 1:numel(names)
    parts{i} = sprintf('%s:%d', names{i}, res(i));
end
p = state.players(playerId);
fprintf('  Res: %s | VP:%d S:%d C:%d R:%d | Army:%d Road:%d\n', ...
    strjoin(parts,'  '), p.victoryPoints, p.settlementCount, p.cityCount, ...
    p.roadCount, p.knightsPlayed, computeLongestRoadLen(state, playerId));
end

function entry = makeHistoryEntry(state, playerId, roll, action)
entry = struct('turn', state.turnIndex, 'player', playerId, 'roll', roll, ...
    'type', action.type, 'vertexId', action.vertexId, 'edgeId', action.edgeId, ...
    'hexId', action.hexId, 'targetPlayer', action.targetPlayer, ...
    'resourceType', action.resourceType, 'resource2', action.resource2, ...
    'vp', state.players(playerId).victoryPoints);
end

function s = formatActionLog(playerId, playerName, action, state, config) %#ok<INUSD>
switch action.type
    case 'pass'
        s = sprintf('P%d (%s) -> pass', playerId, playerName);
    case 'build_settlement'
        s = sprintf('P%d (%s) -> settlement @v%d', playerId, playerName, action.vertexId);
    case 'build_road'
        v1 = state.board.edges(action.edgeId).vertexIds(1);
        v2 = state.board.edges(action.edgeId).vertexIds(2);
        s  = sprintf('P%d (%s) -> road e%d (v%d-v%d)', playerId, playerName, action.edgeId, v1, v2);
    case 'build_city'
        s = sprintf('P%d (%s) -> city @v%d', playerId, playerName, action.vertexId);
    case 'buy_dev_card'
        s = sprintf('P%d (%s) -> bought dev card', playerId, playerName);
    case {'play_knight','move_robber'}
        s = sprintf('P%d (%s) -> %s hex%d steal:P%d', playerId, playerName, action.type, action.hexId, action.targetPlayer);
    case 'play_road_building'
        s = sprintf('P%d (%s) -> road building card', playerId, playerName);
    case 'play_year_of_plenty'
        s = sprintf('P%d (%s) -> year of plenty (%s+%s)', playerId, playerName, action.resourceType, action.resource2);
    case 'play_monopoly'
        s = sprintf('P%d (%s) -> monopoly (%s)', playerId, playerName, action.resourceType);
    case 'maritime_trade'
        s = sprintf('P%d (%s) -> trade %s->%s', playerId, playerName, action.resourceType, action.resource2);
    otherwise
        s = sprintf('P%d (%s) -> %s', playerId, playerName, action.type);
end
s = sprintf('%s | VP=%d', s, state.players(playerId).victoryPoints);
end

%% ========================= LIVE PLAYER AGENT =========================

function action = agent_live(state, legalActions, playerId, config)
fprintf('\n  *** Your turn, Player %d! ***\n', playerId);
res   = state.players(playerId).resources;
names = config.resourceNames;
fprintf('  Resources: ');
for i = 1:numel(names), fprintf('%s=%d  ', names{i}, res(i)); end
p = state.players(playerId);
dc = p.devCards;
fprintf('\n  VP: %d  |  S:%d C:%d R:%d  |  Knights played: %d\n', ...
    p.victoryPoints, p.settlementCount, p.cityCount, p.roadCount, p.knightsPlayed);
fprintf('  Dev cards: Kn:%d RB:%d YP:%d Mon:%d VP:%d  (new this turn: Kn:%d RB:%d YP:%d Mon:%d)\n', ...
    dc.knight, dc.roadBuilding, dc.yearOfPlenty, dc.monopoly, dc.vpCard, ...
    p.newDevCards.knight, p.newDevCards.roadBuilding, p.newDevCards.yearOfPlenty, p.newDevCards.monopoly);
fprintf('  Road length: %d  |  LongestRoad holder: P%d  |  LargestArmy holder: P%d\n', ...
    computeLongestRoadLen(state, playerId), state.longestRoadPlayer, state.largestArmyPlayer);
if state.freeRoads > 0
    fprintf('  [%d free road(s) remaining from Road Building card]\n', state.freeRoads);
end

rates = getTradeRates(state, playerId, config);
fprintf('\n  Legal actions:\n');
for i = 1:numel(legalActions)
    a = legalActions(i);
    switch a.type
        case 'pass'
            fprintf('    %d) pass\n', i);
        case 'build_settlement'
            pos = state.board.vertices(a.vertexId).pos;
            fprintf('    %d) build_settlement  v%d  (%.2f, %.2f)\n', i, a.vertexId, pos(1), pos(2));
        case 'build_road'
            v1 = state.board.edges(a.edgeId).vertexIds(1);
            v2 = state.board.edges(a.edgeId).vertexIds(2);
            fprintf('    %d) build_road  e%d  (v%d--v%d)\n', i, a.edgeId, v1, v2);
        case 'build_city'
            pos = state.board.vertices(a.vertexId).pos;
            fprintf('    %d) build_city  v%d  (%.2f, %.2f)\n', i, a.vertexId, pos(1), pos(2));
        case 'buy_dev_card'
            fprintf('    %d) buy_dev_card  (%d left in deck)\n', i, numel(state.devCardDeck));
        case 'play_knight'
            fprintf('    %d) play_knight -> hex%d, steal from P%d\n', i, a.hexId, a.targetPlayer);
        case 'play_road_building'
            fprintf('    %d) play_road_building (2 free roads)\n', i);
        case 'play_year_of_plenty'
            fprintf('    %d) play_year_of_plenty (%s + %s)\n', i, a.resourceType, a.resource2);
        case 'play_monopoly'
            fprintf('    %d) play_monopoly (%s)\n', i, a.resourceType);
        case 'move_robber'
            fprintf('    %d) move_robber -> hex%d, steal from P%d\n', i, a.hexId, a.targetPlayer);
        case 'maritime_trade'
            ri = resourceIndex(a.resourceType, config.resourceNames);
            fprintf('    %d) trade %d %s -> 1 %s\n', i, rates(ri), a.resourceType, a.resource2);
        otherwise
            fprintf('    %d) %s\n', i, a.type);
    end
end

choice = 0;
while choice < 1 || choice > numel(legalActions) || isnan(choice)
    raw    = input('\n  Enter action number: ','s');
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
fig = figure('Name','Catan Simulation','NumberTitle','off', ...
    'Color',[0.10 0.13 0.20],'Position',[60 60 1360 760]);
axes('Parent',fig,'Position',[0.02 0.04 0.60 0.94], ...
    'Color',[0.16 0.34 0.60],'XColor','none','YColor','none','Tag','board');
axis(findobj(fig,'Tag','board'),'equal');
hold(findobj(fig,'Tag','board'),'on');
axes('Parent',fig,'Position',[0.64 0.04 0.35 0.94], ...
    'Color',[0.08 0.10 0.16],'XColor','none','YColor','none','Tag','info');
hold(findobj(fig,'Tag','info'),'on');
drawBoard(findobj(fig,'Tag','board'), state, config);
drawInfoPanel(findobj(fig,'Tag','info'), state, config, playerNames, 0, 'Setting up board...', 0);
drawnow;
end

function updateGameFig(fig, state, config, playerNames, currentPlayerId, actionStr, rollNum)
if ~ishandle(fig), return; end
ax_board = findobj(fig,'Tag','board');
ax_info  = findobj(fig,'Tag','info');
cla(ax_board); cla(ax_info);
drawBoard(ax_board, state, config);
drawInfoPanel(ax_info, state, config, playerNames, currentPlayerId, actionStr, rollNum);
drawnow;
end

function highlightLegalActions(fig, legalActions, state)
if ~ishandle(fig), return; end
ax = findobj(fig,'Tag','board');
for i = 1:numel(legalActions)
    a = legalActions(i);
    if strcmp(a.type,'build_settlement') || strcmp(a.type,'build_city')
        pos = state.board.vertices(a.vertexId).pos;
        plot(ax, pos(1), pos(2), 'o', 'MarkerSize',20, ...
            'MarkerFaceColor','none','MarkerEdgeColor',[1.0 0.95 0.15],'LineWidth',2.5);
    elseif strcmp(a.type,'build_road')
        v1  = state.board.edges(a.edgeId).vertexIds(1);
        v2  = state.board.edges(a.edgeId).vertexIds(2);
        p1  = state.board.vertices(v1).pos;
        p2  = state.board.vertices(v2).pos;
        mx  = (p1(1)+p2(1))/2;  my = (p1(2)+p2(2))/2;
        plot(ax, mx, my, 'o', 'MarkerSize',10, ...
            'MarkerFaceColor',[1.0 0.95 0.15],'MarkerEdgeColor','none');
    end
end
drawnow;
end

function highlightRobberActions(fig, legalActions, state)
if ~ishandle(fig), return; end
ax = findobj(fig,'Tag','board');
for i = 1:numel(legalActions)
    a = legalActions(i);
    if strcmp(a.type,'move_robber') && a.hexId > 0
        c = state.board.hexes(a.hexId).center;
        theta = linspace(0,2*pi,20);
        plot(ax, c(1)+0.45*cos(theta), c(2)+0.45*sin(theta), '-', ...
            'Color',[1.0 0.3 0.1],'LineWidth',2);
    end
end
drawnow;
end

% -----------------------------------------------------------------
%  Board renderer
% -----------------------------------------------------------------

function drawBoard(ax, state, config) %#ok<INUSD>
hold(ax,'on'); axis(ax,'equal'); axis(ax,'off');
set(ax,'Color',[0.16 0.34 0.60]);
board = state.board;

% --- Hex tiles ---
for h = 1:numel(board.hexes)
    hex  = board.hexes(h);
    vIds = hex.vertexIds;
    xs   = zeros(6,1); ys = zeros(6,1);
    for k = 1:6
        xs(k) = board.vertices(vIds(k)).pos(1);
        ys(k) = board.vertices(vIds(k)).pos(2);
    end
    faceC = hexResourceColor(hex.resourceType);
    patch(ax, xs, ys, faceC, 'EdgeColor',[0.22 0.16 0.08],'LineWidth',2.2);
    cx = hex.center(1); cy = hex.center(2);
    text(ax, cx, cy-0.30, hex.resourceType, 'HorizontalAlignment','center', ...
        'FontSize',7,'FontWeight','bold','Color',[0.10 0.08 0.04]);
    if hex.diceNumber ~= 7
        numColor = [0.08 0.08 0.08];
        if hex.diceNumber==6 || hex.diceNumber==8, numColor=[0.78 0.05 0.05]; end
        theta = linspace(0,2*pi,32);
        patch(ax, cx+0.32*cos(theta), cy+0.10+0.32*sin(theta), [0.96 0.93 0.84], ...
            'EdgeColor',[0.55 0.45 0.30],'LineWidth',1.2);
        text(ax, cx, cy+0.14, num2str(hex.diceNumber), 'HorizontalAlignment','center', ...
            'FontSize',13,'FontWeight','bold','Color',numColor);
        nPips = hexDotCount(hex.diceNumber);
        pipSp = 0.11;
        startPX = cx - (nPips-1)*pipSp/2;
        for d = 1:nPips
            px = startPX + (d-1)*pipSp; py = cy-0.11;
            patch(ax, px+0.035*cos(theta), py+0.035*sin(theta), numColor,'EdgeColor','none');
        end
    end
end

% --- Robber token ---
if isfield(state,'robberHex') && state.robberHex > 0 && state.robberHex <= numel(board.hexes)
    rc = board.hexes(state.robberHex).center;
    theta = linspace(0,2*pi,24);
    patch(ax, rc(1)+0.22*cos(theta), rc(2)+0.55+0.22*sin(theta), ...
        [0.12 0.10 0.08],'EdgeColor',[0.75 0.60 0.30],'LineWidth',1.8);
    text(ax, rc(1), rc(2)+0.55,'R','HorizontalAlignment','center', ...
        'VerticalAlignment','middle','FontSize',9,'FontWeight','bold','Color',[0.95 0.85 0.55]);
end

% --- Port indicators ---
for v = 1:numel(board.vertices)
    if ~strcmp(board.vertices(v).portType,'none')
        pos  = board.vertices(v).pos;
        pc   = portColor(board.vertices(v).portType);
        lbl  = portShortLabel(board.vertices(v).portType);
        plot(ax, pos(1), pos(2), '^', 'MarkerSize',7, ...
            'MarkerFaceColor',pc,'MarkerEdgeColor',[0.9 0.9 0.9],'LineWidth',0.8);
        text(ax, pos(1), pos(2)+0.22, lbl,'HorizontalAlignment','center', ...
            'FontSize',5.5,'Color',[0.95 0.95 0.75],'FontWeight','bold');
    end
end

% --- Roads ---
if isfield(board,'edges')
    for e = 1:numel(board.edges)
        if board.edges(e).owner ~= 0
            v1 = board.edges(e).vertexIds(1);
            v2 = board.edges(e).vertexIds(2);
            p1 = board.vertices(v1).pos;
            p2 = board.vertices(v2).pos;
            pc = playerDisplayColor(board.edges(e).owner);
            plot(ax,[p1(1),p2(1)],[p1(2),p2(2)],'-','Color',pc,'LineWidth',4.5);
        end
    end
end

% --- Vertex ID labels (unoccupied) ---
for v = 1:numel(board.vertices)
    pos = board.vertices(v).pos;
    if board.vertices(v).owner == 0
        text(ax, pos(1), pos(2), num2str(v), 'HorizontalAlignment','center', ...
            'FontSize',5.5,'Color',[0.65 0.68 0.78],'FontAngle','italic');
    end
end

% --- Settlements / Cities ---
for v = 1:numel(board.vertices)
    owner = board.vertices(v).owner;
    if owner ~= 0
        pos = board.vertices(v).pos;
        pc  = playerDisplayColor(owner);
        if board.vertices(v).isCity
            drawCity(ax, pos, owner, pc);
        else
            drawSettlement(ax, pos, owner, pc);
        end
    end
end

title(ax,'Catan Board','Color',[0.90 0.92 0.95],'FontSize',13,'FontWeight','bold');
end

function drawSettlement(ax, pos, owner, pc)
%DRAWSETTLEMENT  House-shaped polygon for a settlement.
sx = pos(1); sy = pos(2);
w = 0.30; wh = 0.19; rh = 0.16;
% Thin dark shadow for depth
hxs = [sx-w/2+0.02, sx+w/2+0.02, sx+w/2+0.02, sx+0.02, sx-w/2+0.02];
hys = [sy-wh/2-0.02, sy-wh/2-0.02, sy+wh/2-0.02, sy+wh/2+rh-0.02, sy+wh/2-0.02];
patch(ax, hxs, hys, [0.05 0.05 0.05], 'EdgeColor','none', 'FaceAlpha',0.5);
% House body
hx = [sx-w/2, sx+w/2, sx+w/2, sx, sx-w/2];
hy = [sy-wh/2, sy-wh/2, sy+wh/2, sy+wh/2+rh, sy+wh/2];
patch(ax, hx, hy, pc, 'EdgeColor',[1 1 1], 'LineWidth',2.0);
% Door
patch(ax, sx+[-0.05 0.05 0.05 -0.05], sy+[-wh/2 -wh/2 -wh/2+0.10 -wh/2+0.10], ...
    pc*0.6, 'EdgeColor',[1 1 1],'LineWidth',0.8);
% Player label
text(ax, sx, sy+0.02, sprintf('P%d', owner), 'HorizontalAlignment','center', ...
    'VerticalAlignment','middle','FontSize',7,'FontWeight','bold','Color','w');
end

function drawCity(ax, pos, owner, pc)
%DRAWCITY  Castle-shaped polygon (wider, with battlements) for a city.
sx = pos(1); sy = pos(2);
w = 0.42; wh = 0.24; rh = 0.19; mw = 0.10; mh = 0.10;
% Gold glow behind city
glow = 0.06;
gx = [sx-w/2-glow, sx+w/2+glow, sx+w/2+glow, sx+glow, sx-glow, sx-w/2-glow];
gy = [sy-wh/2-glow, sy-wh/2-glow, sy+wh/2+glow, sy+wh/2+rh+glow, sy+wh/2+rh+glow, sy+wh/2+glow];
% Simple gold rectangle glow
patch(ax, [sx-w/2-glow, sx+w/2+glow, sx+w/2+glow, sx-w/2-glow], ...
    [sy-wh/2-glow, sy-wh/2-glow, sy+wh/2+rh+glow, sy+wh/2+rh+glow], ...
    [0.95 0.80 0.15], 'EdgeColor','none', 'FaceAlpha',0.55); %#ok<NASGU>
% Shadow
patch(ax, [sx-w/2+0.02, sx+w/2+0.02, sx+w/2+0.02, sx-w/2+0.02], ...
    [sy-wh/2-0.02, sy-wh/2-0.02, sy+wh/2+rh-0.02, sy+wh/2+rh-0.02], ...
    [0.05 0.05 0.05], 'EdgeColor','none', 'FaceAlpha',0.45);
% Main building body
patch(ax, [sx-w/2, sx+w/2, sx+w/2, sx-w/2], [sy-wh/2, sy-wh/2, sy+wh/2, sy+wh/2], ...
    pc, 'EdgeColor',[0.95 0.80 0.15], 'LineWidth',2.5);
% Roof (triangle)
patch(ax, [sx-w/2, sx+w/2, sx], [sy+wh/2, sy+wh/2, sy+wh/2+rh], ...
    pc*0.85, 'EdgeColor',[0.95 0.80 0.15], 'LineWidth',2.5);
% Battlements (3 merlons across the top of the walls)
for mx = [sx-w/2, sx-mw/2, sx+w/2-mw]
    patch(ax, mx+[0 mw mw 0], sy+wh/2+[-0.01 -0.01 mh-0.01 mh-0.01], ...
        pc, 'EdgeColor',[0.95 0.80 0.15], 'LineWidth',1.2);
end
% Door
patch(ax, sx+[-0.06 0.06 0.06 -0.06], sy+[-wh/2 -wh/2 -wh/2+0.12 -wh/2+0.12], ...
    pc*0.5, 'EdgeColor',[0.95 0.80 0.15], 'LineWidth',1.0);
% Player + city label
text(ax, sx, sy+0.01, sprintf('P%d', owner), 'HorizontalAlignment','center', ...
    'VerticalAlignment','middle','FontSize',7,'FontWeight','bold','Color','w');
text(ax, sx, sy+wh/2+rh+0.10, 'CITY', 'HorizontalAlignment','center', ...
    'VerticalAlignment','middle','FontSize',5.5,'FontWeight','bold','Color',[0.95 0.80 0.15]);
end

% -----------------------------------------------------------------
%  Info panel renderer
% -----------------------------------------------------------------

function drawInfoPanel(ax, state, config, playerNames, currentPlayerId, actionStr, rollNum)
cla(ax); axis(ax,'off');
set(ax,'Color',[0.08 0.10 0.16]);
hold(ax,'on'); xlim(ax,[0 1]); ylim(ax,[0 1]);

P = numel(state.players);

text(ax, 0.50, 0.988, 'CATAN','HorizontalAlignment','center','VerticalAlignment','top', ...
    'FontSize',20,'FontWeight','bold','Color',[0.95 0.80 0.18]);

if rollNum > 0
    rollStr = sprintf('Turn %d   |   Roll: %d', state.turnIndex, rollNum);
else
    rollStr = 'Initial Placement';
end
text(ax, 0.50, 0.940, rollStr,'HorizontalAlignment','center','VerticalAlignment','top', ...
    'FontSize',10,'Color',[0.78 0.84 0.92]);

if ~isempty(actionStr)
    text(ax, 0.50, 0.900, actionStr,'HorizontalAlignment','center','VerticalAlignment','top', ...
        'FontSize',8.5,'Color',[0.68 0.82 0.68],'Interpreter','none');
end

% Longest road / Largest army display
bonusStr = '';
if state.longestRoadPlayer ~= 0
    bonusStr = sprintf('LR:P%d  ', state.longestRoadPlayer);
end
if state.largestArmyPlayer ~= 0
    bonusStr = [bonusStr, sprintf('LA:P%d', state.largestArmyPlayer)];
end
if ~isempty(bonusStr)
    text(ax, 0.50, 0.866, bonusStr,'HorizontalAlignment','center','VerticalAlignment','top', ...
        'FontSize',8.5,'Color',[0.95 0.85 0.40],'FontWeight','bold');
end

panelTop    = 0.850;
panelBottom = 0.24;
totalH      = panelTop - panelBottom;
panelH      = totalH / P;

for p = 1:P
    yTop = panelTop - (p-1)*panelH;
    yBot = yTop - panelH + 0.008;
    pc   = playerDisplayColor(p);

    if p == currentPlayerId
        bgColor=[0.17 0.22 0.34]; edgeColor=pc; edgeW=2.2;
    else
        bgColor=[0.12 0.14 0.20]; edgeColor=[0.28 0.30 0.40]; edgeW=1.0;
    end
    patch(ax,[0.03 0.97 0.97 0.03],[yBot yBot yTop-0.006 yTop-0.006], ...
        bgColor,'EdgeColor',edgeColor,'LineWidth',edgeW,'FaceAlpha',1.0);
    patch(ax,[0.03 0.068 0.068 0.03],[yBot yBot yTop-0.006 yTop-0.006],pc,'EdgeColor','none');

    nameStr = sprintf('Player %d  —  %s', p, playerNames{p});
    if p == currentPlayerId, nameStr = [nameStr '  (active)']; end %#ok<AGROW>
    text(ax, 0.09, yTop-0.014, nameStr,'VerticalAlignment','top', ...
        'FontSize',9.5,'FontWeight','bold','Color',pc);

    vp = state.players(p).victoryPoints;
    text(ax, 0.88, yTop-0.010, sprintf('%d VP', vp),'HorizontalAlignment','right', ...
        'VerticalAlignment','top','FontSize',13,'FontWeight','bold','Color',[0.95 0.90 0.65]);

    % Counts row
    pl = state.players(p);
    dc = pl.devCards;
    text(ax, 0.09, yTop-0.014-0.040, ...
        sprintf('S:%d  C:%d  R:%d  |  Kn:%d RB:%d YP:%d Mon:%d VP:%d', ...
        pl.settlementCount, pl.cityCount, pl.roadCount, ...
        dc.knight, dc.roadBuilding, dc.yearOfPlenty, dc.monopoly, dc.vpCard), ...
        'VerticalAlignment','top','FontSize',7,'Color',[0.82 0.86 0.90]);

    % Resources row
    res    = pl.resources;
    rNames = config.resourceNames;
    shortN = {'Wd','Bk','Sh','Wh','Or'};
    resX   = 0.09;
    resY   = yTop - 0.014 - 0.085;
    boxW   = 0.155;
    boxH   = panelH * 0.28;
    for ri = 1:numel(rNames)
        bx = resX + (ri-1)*boxW;
        patch(ax, bx+[0 boxW-0.01 boxW-0.01 0], resY+[-boxH -boxH 0 0], ...
            hexResourceColor(rNames{ri}),'EdgeColor',[0.20 0.18 0.15],'LineWidth',0.8);
        text(ax, bx+(boxW-0.01)/2, resY-0.002, shortN{ri}, ...
            'HorizontalAlignment','center','VerticalAlignment','top', ...
            'FontSize',6.5,'Color',[0.12 0.10 0.08],'FontWeight','bold');
        text(ax, bx+(boxW-0.01)/2, resY-boxH/2-0.002, num2str(res(ri)), ...
            'HorizontalAlignment','center','VerticalAlignment','middle', ...
            'FontSize',10,'FontWeight','bold','Color',[0.05 0.05 0.05]);
    end
end

text(ax, 0.50, panelBottom-0.010, ...
    sprintf('First to %d VP wins  |  Longest Road (5+) = 2VP  |  Largest Army (3+) = 2VP', config.winVP), ...
    'HorizontalAlignment','center','VerticalAlignment','top','FontSize',7.5,'Color',[0.50 0.54 0.62]);

% Resource legend
legendTop = panelBottom - 0.055;
text(ax, 0.50, legendTop,'Resource Legend','HorizontalAlignment','center','VerticalAlignment','top', ...
    'FontSize',8.5,'FontWeight','bold','Color',[0.72 0.74 0.82]);
rTypes  = {'wood','brick','sheep','wheat','ore','desert'};
cols    = 3; lBoxW = 0.24; lBoxH = 0.038; lStartX = 0.07;
lStartY = legendTop - 0.032;
for ri = 1:numel(rTypes)
    row = floor((ri-1)/cols); col = mod(ri-1,cols);
    bx  = lStartX + col*(lBoxW+0.04);
    by  = lStartY - row*(lBoxH+0.012);
    patch(ax, bx+[0 lBoxW lBoxW 0], by+[-lBoxH -lBoxH 0 0], hexResourceColor(rTypes{ri}), ...
        'EdgeColor',[0.30 0.28 0.22],'LineWidth',1.0);
    text(ax, bx+lBoxW+0.015, by-lBoxH/2, rTypes{ri},'VerticalAlignment','middle', ...
        'FontSize',7.5,'Color',[0.78 0.80 0.88]);
end
end

%% ========================= COLOR HELPERS =========================

function c = hexResourceColor(rType)
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
colors = [0.92 0.22 0.22; 0.25 0.52 0.96; 0.96 0.66 0.10; 0.24 0.82 0.36];
if playerId == 0, c = [0.50 0.50 0.50];
else, c = colors(mod(playerId-1, size(colors,1))+1, :); end
end

function n = hexDotCount(diceNum)
dotMap = [1 2 3 4 5 0 5 4 3 2 1];
if diceNum < 2 || diceNum > 12, n = 0;
else, n = dotMap(diceNum-1); end
end

function c = portColor(portType)
switch portType
    case '3to1',      c = [0.70 0.70 0.70];
    case 'wood2to1',  c = [0.18 0.50 0.18];
    case 'brick2to1', c = [0.74 0.28 0.08];
    case 'sheep2to1', c = [0.62 0.88 0.32];
    case 'wheat2to1', c = [0.94 0.82 0.12];
    case 'ore2to1',   c = [0.52 0.54 0.60];
    otherwise,        c = [0.70 0.70 0.70];
end
end

function s = portShortLabel(portType)
switch portType
    case '3to1',      s = '3:1';
    case 'wood2to1',  s = '2:1Wd';
    case 'brick2to1', s = '2:1Bk';
    case 'sheep2to1', s = '2:1Sh';
    case 'wheat2to1', s = '2:1Wh';
    case 'ore2to1',   s = '2:1Or';
    otherwise,        s = '?';
end
end

%% ========================= BOARD GENERATION =========================

function board = createCatanBoard()
axial    = axialCoordsRadius2();
numHexes = size(axial, 1);
sizeHex  = 1.0;
angles   = deg2rad(30 + (0:5)*60);

resourceBag = [repmat({'wood'},1,4), repmat({'brick'},1,3), ...
               repmat({'sheep'},1,4), repmat({'wheat'},1,4), ...
               repmat({'ore'},1,3), {'desert'}];
resourceBag = resourceBag(randperm(numel(resourceBag)));

numberBag = [2 12, 3 3, 4 4, 5 5, 6 6, 8 8, 9 9, 10 10, 11 11];
numberBag = numberBag(randperm(numel(numberBag)));

diceNumbers = zeros(1, numHexes);
ndx = 1;
for h = 1:numHexes
    if strcmp(resourceBag{h},'desert')
        diceNumbers(h) = 7;
    else
        diceNumbers(h) = numberBag(ndx); ndx = ndx + 1;
    end
end

% Build vertices
vertexMap      = containers.Map('KeyType','char','ValueType','int32');
vertexPos      = zeros(0, 2);
vertexAdjHexes = {};
hexVertexIds   = zeros(numHexes, 6);

for h = 1:numHexes
    center = axialToCartesian(axial(h,:), sizeHex);
    for k = 1:6
        pos = center + sizeHex * [cos(angles(k)), sin(angles(k))];
        key = vertexKey(pos);
        if ~isKey(vertexMap, key)
            newId = size(vertexPos,1) + 1;
            vertexMap(key)        = newId;
            vertexPos(newId,:)    = pos;
            vertexAdjHexes{newId} = h; %#ok<AGROW>
            vId = newId;
        else
            vId = vertexMap(key);
            vertexAdjHexes{vId} = unique([vertexAdjHexes{vId}, h]);
        end
        hexVertexIds(h,k) = vId;
    end
end

numVertices = size(vertexPos, 1);

% Build adjacency matrix for vertices
adjMat = false(numVertices);
for h = 1:numHexes
    ids = hexVertexIds(h,:);
    for k = 1:6
        a = ids(k); b = ids(mod(k,6)+1);
        adjMat(a,b) = true; adjMat(b,a) = true;
    end
end

% Initialize vertex structs
vertices = repmat(struct('owner',0,'isCity',false,'portType','none', ...
    'adjHexIds',[],'adjVertexIds',[],'adjEdgeIds',[],'pos',[0,0]), 1, numVertices);
for v = 1:numVertices
    vertices(v).owner        = 0;
    vertices(v).isCity       = false;
    vertices(v).portType     = 'none';
    vertices(v).adjHexIds    = sort(vertexAdjHexes{v});
    vertices(v).adjVertexIds = find(adjMat(v,:));
    vertices(v).adjEdgeIds   = [];
    vertices(v).pos          = vertexPos(v,:);
end

% Build edges
edgeMap  = containers.Map('KeyType','char','ValueType','int32');
edgeList = struct('vertexIds',{},'owner',{},'adjHexIds',{});
eCount   = 0;
for v1 = 1:numVertices
    nbrs = find(adjMat(v1,:));
    for v2 = nbrs
        if v2 <= v1, continue; end
        eCount = eCount + 1;
        key = sprintf('%d_%d', v1, v2);
        edgeMap(key) = eCount;
        edgeList(eCount).vertexIds = [v1, v2];
        edgeList(eCount).owner     = 0;
        edgeList(eCount).adjHexIds = [];
        vertices(v1).adjEdgeIds(end+1) = eCount;
        vertices(v2).adjEdgeIds(end+1) = eCount;
    end
end

% Compute adjHexIds for each edge
for h = 1:numHexes
    ids = hexVertexIds(h,:);
    for k = 1:6
        v1 = min(ids(k), ids(mod(k,6)+1));
        v2 = max(ids(k), ids(mod(k,6)+1));
        key = sprintf('%d_%d', v1, v2);
        if isKey(edgeMap, key)
            eid = edgeMap(key);
            edgeList(eid).adjHexIds = unique([edgeList(eid).adjHexIds, h]);
        end
    end
end

% Assign ports to coastal edges (adjacent to exactly 1 hex)
coastEdgeIds = [];
for e = 1:eCount
    if numel(edgeList(e).adjHexIds) == 1
        coastEdgeIds(end+1) = e; %#ok<AGROW>
    end
end

portTypes = {'3to1','3to1','3to1','3to1', ...
             'wood2to1','brick2to1','sheep2to1','wheat2to1','ore2to1'};
portTypes = portTypes(randperm(9));
nPorts    = min(9, numel(coastEdgeIds));
% Sort coastal edges by angle around board center, then pick evenly spaced
% ones so ports are distributed around the perimeter instead of clustering.
coastMidpoints = zeros(numel(coastEdgeIds), 2);
for ci = 1:numel(coastEdgeIds)
    eid = coastEdgeIds(ci);
    p1 = vertexPos(edgeList(eid).vertexIds(1), :);
    p2 = vertexPos(edgeList(eid).vertexIds(2), :);
    coastMidpoints(ci,:) = (p1 + p2) / 2;
end
angles_coast = atan2(coastMidpoints(:,2), coastMidpoints(:,1));
[~, sortIdx] = sort(angles_coast);
coastEdgeIds = coastEdgeIds(sortIdx);
step = numel(coastEdgeIds) / nPorts;
offset = randi(round(step));
pickIdx = mod(round((0:nPorts-1)*step + offset - 1), numel(coastEdgeIds)) + 1;
portEdges = coastEdgeIds(pickIdx);
for i = 1:nPorts
    eid  = portEdges(i);
    pType = portTypes{i};
    v1   = edgeList(eid).vertexIds(1);
    v2   = edgeList(eid).vertexIds(2);
    vertices(v1).portType = pType;
    vertices(v2).portType = pType;
end

% Build hex structs
hexes = repmat(struct('resourceType','','diceNumber',0,'vertexIds',zeros(1,6),'center',[0,0]), ...
    1, numHexes);
for h = 1:numHexes
    hexes(h).resourceType = resourceBag{h};
    hexes(h).diceNumber   = diceNumbers(h);
    hexes(h).vertexIds    = hexVertexIds(h,:);
    hexes(h).center       = axialToCartesian(axial(h,:), sizeHex);
end

board = struct('hexes',hexes,'vertices',vertices,'edges',edgeList,'edgeMap',edgeMap);
end

function axial = axialCoordsRadius2()
R      = 2;
coords = zeros(0, 2);
for q = -R:R
    for r = -R:R
        s = -q - r;
        if max([abs(q),abs(r),abs(s)]) <= R
            coords(end+1,:) = [q, r]; %#ok<AGROW>
        end
    end
end
axial = coords;
end

function xy = axialToCartesian(qr, scale)
q  = qr(1); r = qr(2);
xy = scale * [sqrt(3)*(q + r/2), 1.5*r];
end

function key = vertexKey(pos)
key = sprintf('%.6f_%.6f', round(pos(1),6), round(pos(2),6));
end

function fn = resolveAgentFn(name)
switch lower(name)
    case 'random',      fn = @agent_random;
    case 'heuristic',   fn = @agent_heuristic;
    case 'monte_carlo', fn = @agent_montecarlo;
    case 'mcts',        fn = @agent_mcts;
    otherwise
        error('Unknown agent "%s". Choose from: random, heuristic, monte_carlo, mcts.', name);
end
end