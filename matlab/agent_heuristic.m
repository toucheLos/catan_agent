function action = agent_heuristic(state, legalActions, playerId, config)
%AGENT_HEURISTIC  Greedy agent: scores every legal action, picks the best.
%
% Scoring philosophy
% ------------------
%  build_settlement  — production value + resource need + diversity + blocking
%  build_road        — production-weighted new settlement spots opened
%  build_city        — production gain × resource need of what the city will produce
%  buy_dev_card      — dynamic: higher when resources are stockpiled with no other build
%  maritime_trade    — build-completion bonus; otherwise need/surplus balance
%  move_robber/knight— disruption to opponent × dice probability; steal value
%  play_road_building— sum of top-2 production-weighted road values
%  play_year_of_plenty—build-completion detection; falls back to need scoring
%  play_monopoly     — expected resource stolen from opponents

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
            score = scoreDevCard(state, playerId, config);
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

%% =========================================================================
%  Settlement
%% =========================================================================

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
    demand  = config.buildCosts.settlement(rIdx) + config.buildCosts.road(rIdx);
    missing = max(demand - player.resources(rIdx), 0);
    needScore = needScore + p * missing;
end

% Robber penalty: building on a hex where the robber currently sits is risky
robberPenalty = 0;
for h = vertex.adjHexIds
    if h == state.robberHex
        p = catan_core('diceProbability', state.board.hexes(h).diceNumber);
        robberPenalty = robberPenalty + p * 0.5;
    end
end

existing    = currentCoverage(state, playerId, config);
newCoverage = sum(producedTypes & ~existing);

blocking = 0;
for nv = vertex.adjVertexIds
    ow = state.board.vertices(nv).owner;
    if ow ~= 0 && ow ~= playerId, blocking = blocking + 1; end
end

score = wProd*prodScore + wNeed*needScore + wDiv*newCoverage + wBlock*blocking - robberPenalty;
end

%% =========================================================================
%  Road  — weight new spots by their production value, not raw count
%% =========================================================================

function score = scoreRoad(state, playerId, edgeId, config)
wRoad = 1.8;
if isfield(config,'heuristic') && isfield(config.heuristic,'wRoad')
    wRoad = config.heuristic.wRoad;
end

% Temporarily place the road and find newly accessible settlement spots
tempState = state;
tempState.board.edges(edgeId).owner = playerId;

newSpotValue = 0;
for v = 1:numel(tempState.board.vertices)
    if tempState.board.vertices(v).owner ~= 0, continue; end
    if config.enforceDistanceRule
        ok = true;
        for nv = tempState.board.vertices(v).adjVertexIds
            if tempState.board.vertices(nv).owner ~= 0, ok = false; break; end
        end
        if ~ok, continue; end
    end
    % Newly accessible?
    if ~hasRoadAtVertex(tempState, playerId, v), continue; end
    if hasRoadAtVertex(state, playerId, v), continue; end

    % Value this spot by its production potential
    spotProd = 0;
    for h = tempState.board.vertices(v).adjHexIds
        hex = tempState.board.hexes(h);
        if strcmp(hex.resourceType,'desert'), continue; end
        p = catan_core('diceProbability', hex.diceNumber);
        % Discount spots near the robber
        if h == state.robberHex, p = p * 0.4; end
        spotProd = spotProd + p;
    end
    newSpotValue = newSpotValue + spotProd;
end

if newSpotValue < 1e-6
    % Road opens no new spots — still worth a little for longest-road progress
    score = 0.25 + longestRoadProgress(state, playerId, edgeId);
else
    score = wRoad * newSpotValue;
end
end

function bonus = longestRoadProgress(state, playerId, edgeId)
% Small bonus if this road extends toward matching/beating opponent road length
tempState = state;
tempState.board.edges(edgeId).owner = playerId;
myLen  = computeLongestRoadLen(tempState, playerId);
curLen = computeLongestRoadLen(state, playerId);
if myLen > curLen
    bonus = 0.15 * (myLen - curLen);
    % Extra bonus if this crosses threshold 5 (longest road claim)
    if curLen < 5 && myLen >= 5, bonus = bonus + 1.0; end
else
    bonus = 0;
end
end

%% =========================================================================
%  City  — weight production by resource need (not just raw dice probability)
%% =========================================================================

function score = scoreCity(state, playerId, vertexId, config)
wCity = 2.5;
if isfield(config,'heuristic') && isfield(config.heuristic,'wCity')
    wCity = config.heuristic.wCity;
end

vertex = state.board.vertices(vertexId);
player = state.players(playerId);

% A city adds +1× production at each adjacent hex.
% Weight each +1 by how much that resource is still needed.
gainScore = 0;
for h = vertex.adjHexIds
    hex  = state.board.hexes(h);
    if strcmp(hex.resourceType,'desert'), continue; end
    p    = catan_core('diceProbability', hex.diceNumber);
    if h == state.robberHex, p = p * 0.5; end
    rIdx = find(strcmp(config.resourceNames, hex.resourceType), 1);
    if isempty(rIdx), continue; end

    % How useful is one more of this resource?
    % Build demand = what all buildings cost combined
    buildDemand = config.buildCosts.settlement(rIdx) + config.buildCosts.road(rIdx) + ...
                  config.buildCosts.city(rIdx) + config.buildCosts.devCard(rIdx);
    have = player.resources(rIdx);
    needFactor = max(0.5, buildDemand / max(1, have));  % at least 0.5 even if stockpiled

    gainScore = gainScore + p * needFactor;
end

score = wCity * gainScore;
end

%% =========================================================================
%  Dev card — dynamic value based on game state
%% =========================================================================

function score = scoreDevCard(state, playerId, config)
player   = state.players(playerId);
totalRes = sum(player.resources);

% Base value — rises when we have surplus resources with no immediate build
base = 1.0;

% Higher when we're resource-rich but can't build (dev card is good outlet)
canSettle = canAffordCheck(player.resources, config.buildCosts.settlement);
canCity   = canAffordCheck(player.resources, config.buildCosts.city);
if ~canSettle && ~canCity && totalRes >= 4
    base = base + 0.6;
end

% Lower when deck is nearly empty (fewer cards to potentially draw VP cards)
deckSize = numel(state.devCardDeck);
if deckSize <= 3,  base = base * 0.5;
elseif deckSize <= 8, base = base * 0.75; end

% Bonus late game when VP cards could push us to win
vp      = state.players(playerId).victoryPoints;
winVP   = config.winVP;
if vp >= winVP - 3, base = base + 0.8; end

score = base;
end

%% =========================================================================
%  Trade  — build-completion detection is the key improvement
%% =========================================================================

function score = scoreTrade(state, playerId, action, config)
giveIdx  = find(strcmp(config.resourceNames, action.resourceType), 1);
recvIdx  = find(strcmp(config.resourceNames, action.resource2), 1);
rates    = getTradeRates(state, playerId, config);
rate     = rates(giveIdx);
player   = state.players(playerId);

% Simulate resources after trade
resAfter = player.resources;
resAfter(giveIdx) = resAfter(giveIdx) - rate;
resAfter(recvIdx) = resAfter(recvIdx) + 1;

if resAfter(giveIdx) < 0, score = -2.0; return; end  % can't afford

% --- Build completion check (highest priority) ---
% Does this trade let us build something we couldn't before?
buildValues = [2.5, 0.8, 2.0, 1.0];  % settlement, road, city, devCard
buildCosts  = {config.buildCosts.settlement, config.buildCosts.road, ...
               config.buildCosts.city, config.buildCosts.devCard};

completionBonus = 0;
for b = 1:4
    couldBefore = canAffordCheck(player.resources, buildCosts{b});
    canNow      = canAffordCheck(resAfter, buildCosts{b});
    if canNow && ~couldBefore
        completionBonus = completionBonus + buildValues(b);
    end
end
if completionBonus > 0
    % Discount by trade cost (4:1 is expensive; 2:1 is essentially free)
    score = completionBonus - (rate - 2) * 0.3;
    return;
end

% --- No build unlocked: only trade if we have genuine surplus and genuine need ---
surplus = player.resources(giveIdx) - rate;  % how many we keep after trading
totalNeed = config.buildCosts.settlement(recvIdx) + config.buildCosts.road(recvIdx) + ...
            config.buildCosts.city(recvIdx) + config.buildCosts.devCard(recvIdx);
needGet   = max(0, totalNeed - player.resources(recvIdx));

if needGet == 0
    score = -0.6;  % already have plenty of that resource
    return;
end
if surplus < 0
    score = -0.8;  % would leave us short on the resource we're giving
    return;
end

score = 0.5 * needGet - 0.2 * (rate - 2) + 0.05 * surplus;
end

%% =========================================================================
%  Robber / Knight
%% =========================================================================

function score = scoreRobber(state, playerId, action, config) %#ok<INUSD>
h = action.hexId;
if h < 1 || h > numel(state.board.hexes), score = 0; return; end
hex  = state.board.hexes(h);
prob = catan_core('diceProbability', hex.diceNumber);

ownOnHex = 0; oppOnHex = 0;
for vid = hex.vertexIds
    ow = state.board.vertices(vid).owner;
    if ow == playerId, ownOnHex = ownOnHex + 1;
    elseif ow ~= 0,    oppOnHex = oppOnHex + 1; end
end

% Steal from the richest opponent on the hex
stealVal = 0;
if action.targetPlayer ~= 0
    tp       = action.targetPlayer;
    stealVal = sum(state.players(tp).resources) * 0.12;
    % Bonus for stealing from leader
    [~, leader] = max([state.players.victoryPoints]);
    if tp == leader, stealVal = stealVal * 1.3; end
end

% Penalty for moving robber onto own production hex
ownPenalty = prob * ownOnHex * 1.5;

score = prob * oppOnHex * 1.2 + stealVal - ownPenalty;
end

%% =========================================================================
%  Road Building dev card
%% =========================================================================

function score = scoreRoadBuilding(state, playerId, config)
% Value = sum of best 2 production-weighted road scores
roadScores = [];
for e = 1:numel(state.board.edges)
    if canBuildRoadAtEdge(state, playerId, e)
        roadScores(end+1) = scoreRoad(state, playerId, e, config); %#ok<AGROW>
    end
end
if isempty(roadScores), score = 0.5; return; end
roadScores = sort(roadScores, 'descend');
if numel(roadScores) >= 2
    score = roadScores(1) + roadScores(2) + 0.3;  % bonus for free
else
    score = roadScores(1) * 2 + 0.3;
end
end

%% =========================================================================
%  Year of Plenty  — detect build completion
%% =========================================================================

function score = scoreYearOfPlenty(state, playerId, action, config)
r1 = find(strcmp(config.resourceNames, action.resourceType), 1);
r2 = find(strcmp(config.resourceNames, action.resource2),    1);
player = state.players(playerId);

% Simulate receiving both resources
resAfter = player.resources;
resAfter(r1) = resAfter(r1) + 1;
resAfter(r2) = resAfter(r2) + 1;

% Check if this enables a build
buildValues = [2.5, 0.8, 2.0, 1.0];
buildCosts  = {config.buildCosts.settlement, config.buildCosts.road, ...
               config.buildCosts.city, config.buildCosts.devCard};

completionBonus = 0;
for b = 1:4
    couldBefore = canAffordCheck(player.resources, buildCosts{b});
    canNow      = canAffordCheck(resAfter, buildCosts{b});
    if canNow && ~couldBefore
        completionBonus = completionBonus + buildValues(b);
    end
end

if completionBonus > 0
    score = completionBonus + 0.5;  % free resources are always good
    return;
end

% Fallback: raw need score
totalNeed1 = config.buildCosts.settlement(r1) + config.buildCosts.road(r1) + config.buildCosts.city(r1);
totalNeed2 = config.buildCosts.settlement(r2) + config.buildCosts.road(r2) + config.buildCosts.city(r2);
need1 = max(0, totalNeed1 - player.resources(r1));
need2 = max(0, totalNeed2 - player.resources(r2));
score = 0.8 * (need1 + need2) + 0.6;
end

%% =========================================================================
%  Monopoly
%% =========================================================================

function score = scoreMonopoly(state, playerId, action, config) %#ok<INUSD>
rIdx  = find(strcmp(config.resourceNames, action.resourceType), 1);
total = 0;
for op = 1:numel(state.players)
    if op == playerId, continue; end
    total = total + state.players(op).resources(rIdx);
end
% Adjust for how much we can use the resource ourselves
needFactor = config.buildCosts.settlement(rIdx) + config.buildCosts.road(rIdx) + ...
             config.buildCosts.city(rIdx) + config.buildCosts.devCard(rIdx);
score = total * 0.5 * max(0.5, needFactor);
end

%% =========================================================================
%  Helpers
%% =========================================================================

function tf = canAffordCheck(resources, cost)
tf = all(resources >= cost);
end

function n = countNewSettlementSpots(state, playerId, edgeId, config)
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
    if state.board.vertices(v).owner ~= 0, continue; end
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

function len = computeLongestRoadLen(state, playerId)
% Local copy of the road DFS for scoring purposes
board = state.board;
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
len = 0;
usedE = false(1, numEdges);
for sv = startVerts
    l = dfsRoadLocal(board, playerId, sv, usedE);
    if l > len, len = l; end
end
end

function len = dfsRoadLocal(board, playerId, v, usedEdges)
len = 0;
for e = board.vertices(v).adjEdgeIds
    if board.edges(e).owner ~= playerId, continue; end
    if usedEdges(e), continue; end
    vPair = board.edges(e).vertexIds;
    nv = vPair(vPair ~= v); if isempty(nv), continue; end
    nv = nv(1);
    nOwner = board.vertices(nv).owner;
    if nOwner ~= 0 && nOwner ~= playerId
        if 1 > len, len = 1; end
    else
        usedEdges(e) = true;
        sl = 1 + dfsRoadLocal(board, playerId, nv, usedEdges);
        usedEdges(e) = false;
        if sl > len, len = sl; end
    end
end
end
