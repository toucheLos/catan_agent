function action = agent_heuristic(state, legalActions, playerId, config)
%AGENT_HEURISTIC  Greedy agent scoring all Catan action types.

bestScore  = -inf;
bestAction = catan_core('makeAction', 'pass', 0);

for i = 1:numel(legalActions)
    a = legalActions(i);
    switch a.type
        case 'pass'
            score = -0.05;
        case 'build_settlement'
            score = scoreSettlement(state, playerId, a.vertexId, config);
        case 'build_road'
            score = scoreRoad(state, playerId, a.edgeId, config);
        case 'build_city'
            score = scoreCity(state, playerId, a.vertexId, config);
        case 'buy_dev_card'
            score = 1.2;  % moderate fixed value
        case 'maritime_trade'
            score = scoreTrade(state, playerId, a, config);
        case {'move_robber','play_knight'}
            score = scoreRobber(state, playerId, a, config);
            if strcmp(a.type,'play_knight'), score = score + 0.4; end
        case 'play_road_building'
            score = scoreRoadBuilding(state, playerId, config);
        case 'play_year_of_plenty'
            score = scoreYearOfPlenty(state, playerId, a, config);
        case 'play_monopoly'
            score = scoreMonopoly(state, playerId, a, config);
        otherwise
            score = -inf;
    end
    if score > bestScore
        bestScore  = score;
        bestAction = a;
    end
end

action = bestAction;
end

% =========================================================================
%  Scoring helpers
% =========================================================================

function score = scoreSettlement(state, playerId, vertexId, config)
player = state.players(playerId);
vertex = state.board.vertices(vertexId);

wProd   = 3.0; wNeed = 1.5; wDiv = 1.0; wBlock = 0.2;
if isfield(config,'heuristic')
    hw = config.heuristic;
    if isfield(hw,'wExpectedProduction'), wProd  = hw.wExpectedProduction; end
    if isfield(hw,'wResourceNeed'),       wNeed  = hw.wResourceNeed;       end
    if isfield(hw,'wDiversity'),          wDiv   = hw.wDiversity;          end
    if isfield(hw,'wBlocking'),           wBlock = hw.wBlocking;           end
end

prodScore = 0; needScore = 0;
producedTypes = false(1, numel(config.resourceNames));

for h = vertex.adjHexIds
    hex  = state.board.hexes(h);
    p    = catan_core('diceProbability', hex.diceNumber);
    rIdx = find(strcmp(config.resourceNames, hex.resourceType), 1);
    if isempty(rIdx), continue; end
    prodScore = prodScore + p;
    producedTypes(rIdx) = true;
    demand  = config.buildCosts.settlement(rIdx);
    missing = max(demand - player.resources(rIdx), 0);
    needScore = needScore + p * missing;
end

existing    = currentCoverage(state, playerId, config);
newCoverage = sum(producedTypes & ~existing);

blocking = 0;
for nv = vertex.adjVertexIds
    ow = state.board.vertices(nv).owner;
    if ow ~= 0 && ow ~= playerId, blocking = blocking + 1; end
end

score = wProd*prodScore + wNeed*needScore + wDiv*newCoverage + wBlock*blocking;
end

function score = scoreRoad(state, playerId, edgeId, config)
wRoad = 1.8;
if isfield(config,'heuristic') && isfield(config.heuristic,'wRoad')
    wRoad = config.heuristic.wRoad;
end
n     = countNewSettlementSpots(state, playerId, edgeId, config);
score = wRoad * n;
% Small bonus for extending toward high-production areas
if n == 0
    % At least credit the road for future flexibility
    score = 0.3;
end
end

function score = scoreCity(state, playerId, vertexId, config)
wCity = 2.5;
if isfield(config,'heuristic') && isfield(config.heuristic,'wCity')
    wCity = config.heuristic.wCity;
end
vertex = state.board.vertices(vertexId);
prod   = 0;
for h = vertex.adjHexIds
    prod = prod + catan_core('diceProbability', state.board.hexes(h).diceNumber);
end
score = wCity * prod;  % city doubles production
end

function score = scoreTrade(state, playerId, action, config)
giveIdx  = find(strcmp(config.resourceNames, action.resourceType), 1);
recvIdx  = find(strcmp(config.resourceNames, action.resource2), 1);
rates    = getTradeRates(state, playerId, config);
rate     = rates(giveIdx);
player   = state.players(playerId);

% Utility of receiving resource (how much do we need it?)
totalNeed = config.buildCosts.settlement(recvIdx) + config.buildCosts.road(recvIdx) ...
          + config.buildCosts.city(recvIdx) + config.buildCosts.devCard(recvIdx);
have      = player.resources(recvIdx);
needGet   = max(0, totalNeed - have);

% Cost of giving: how much surplus do we have?
surplus   = max(0, player.resources(giveIdx) - rate);

% Only trade if genuinely useful (need > 0, not trading for something already stockpiled)
if needGet == 0, score = -0.5; return; end

score = 0.8 * needGet - 0.15 * (rate - 2) + 0.05 * surplus;
end

function score = scoreRobber(state, playerId, action, config) %#ok<INUSD>
h = action.hexId;
if h < 1 || h > numel(state.board.hexes), score = 0; return; end
hex  = state.board.hexes(h);
prob = catan_core('diceProbability', hex.diceNumber);

ownOnHex = 0; oppOnHex = 0;
for vid = hex.vertexIds
    ow = state.board.vertices(vid).owner;
    if ow == playerId,                        ownOnHex = ownOnHex + 1;
    elseif ow ~= 0,                           oppOnHex = oppOnHex + 1; end
end

stealVal = 0;
if action.targetPlayer ~= 0
    tp       = action.targetPlayer;
    stealVal = sum(state.players(tp).resources) * 0.10;
end

score = prob * (oppOnHex - 2*ownOnHex) + stealVal;
end

function score = scoreRoadBuilding(state, playerId, config)
% Approximate: value of the best 2 roads we could build
board = state.board;
scores = [];
for e = 1:numel(board.edges)
    if canBuildRoadAtEdge(state, playerId, e)
        scores(end+1) = countNewSettlementSpots(state, playerId, e, config); %#ok<AGROW>
    end
end
if isempty(scores), score = 0.5; return; end
scores = sort(scores,'descend');
if numel(scores) >= 2
    score = 1.8 * (scores(1) + scores(2));
else
    score = 1.8 * scores(1) * 2;
end
end

function score = scoreYearOfPlenty(state, playerId, action, config)
r1 = find(strcmp(config.resourceNames, action.resourceType), 1);
r2 = find(strcmp(config.resourceNames, action.resource2),    1);
player = state.players(playerId);
totalNeed1 = config.buildCosts.settlement(r1)+config.buildCosts.road(r1)+config.buildCosts.city(r1);
totalNeed2 = config.buildCosts.settlement(r2)+config.buildCosts.road(r2)+config.buildCosts.city(r2);
need1 = max(0, totalNeed1 - player.resources(r1));
need2 = max(0, totalNeed2 - player.resources(r2));
score = 0.8 * (need1 + need2) + 0.5;
end

function score = scoreMonopoly(state, playerId, action, config) %#ok<INUSD>
rIdx = find(strcmp(config.resourceNames, action.resourceType), 1);
total = 0;
for op = 1:numel(state.players)
    if op == playerId, continue; end
    total = total + state.players(op).resources(rIdx);
end
score = total * 0.6;
end

% =========================================================================
%  Helpers
% =========================================================================

function n = countNewSettlementSpots(state, playerId, edgeId, config)
% Count valid settlement vertices that become accessible by adding this road.
tempState = state;
tempState.board.edges(edgeId).owner = playerId;
n = 0;
for v = 1:numel(tempState.board.vertices)
    if tempState.board.vertices(v).owner ~= 0, continue; end
    if config.enforceDistanceRule
        ok = true;
        for nv = tempState.board.vertices(v).adjVertexIds
            if tempState.board.vertices(nv).owner ~= 0, ok = false; break; end
        end
        if ~ok, continue; end
    end
    % Newly accessible = connected now but not before
    if hasRoadAtVertex(tempState, playerId, v) && ~hasRoadAtVertex(state, playerId, v)
        n = n + 1;
    end
end
end

function tf = hasRoadAtVertex(state, playerId, v)
for e = state.board.vertices(v).adjEdgeIds
    if state.board.edges(e).owner == playerId, tf = true; return; end
end
tf = false;
end

function tf = canBuildRoadAtEdge(state, playerId, e)
tf = false;
if state.board.edges(e).owner ~= 0, return; end
vPair = state.board.edges(e).vertexIds;
for k = 1:2
    v = vPair(k);
    if state.board.vertices(v).owner == playerId, tf = true; return; end
    if state.board.vertices(v).owner ~= 0, continue; end % opponent blocks
    for e2 = state.board.vertices(v).adjEdgeIds
        if e2 ~= e && state.board.edges(e2).owner == playerId, tf = true; return; end
    end
end
end

function rates = getTradeRates(state, playerId, config)
rates = 4 * ones(1, numel(config.resourceNames));
for v = 1:numel(state.board.vertices)
    if state.board.vertices(v).owner ~= playerId, continue; end
    port = state.board.vertices(v).portType;
    if strcmp(port,'none'), continue; end
    if strcmp(port,'3to1')
        rates = min(rates, 3);
    else
        rName = port(1:end-4);
        rIdx  = find(strcmp(config.resourceNames, rName), 1);
        if ~isempty(rIdx), rates(rIdx) = min(rates(rIdx), 2); end
    end
end
end

function coverage = currentCoverage(state, playerId, config)
coverage = false(1, numel(config.resourceNames));
for v = 1:numel(state.board.vertices)
    if state.board.vertices(v).owner ~= playerId, continue; end
    for h = state.board.vertices(v).adjHexIds
        rIdx = find(strcmp(config.resourceNames, state.board.hexes(h).resourceType), 1);
        if ~isempty(rIdx), coverage(rIdx) = true; end
    end
end
end
