function action = agent_heuristic(state, legalActions, playerId, config)
%AGENT_HEURISTIC Greedy settlement placement based on production + coverage.

bestScore = -inf;
bestAction = catan_core('makeAction', 'pass', 0);

for i = 1:numel(legalActions)
    a = legalActions(i);

    if strcmp(a.type, 'pass')
        score = -0.05;
    elseif strcmp(a.type, 'build_settlement')
        score = scoreSettlementVertex(state, playerId, a.vertexId, config);
    else
        score = -inf;
    end

    if score > bestScore
        bestScore = score;
        bestAction = a;
    end
end

action = bestAction;

end

function score = scoreSettlementVertex(state, playerId, vertexId, config)
player = state.players(playerId);
vertex = state.board.vertices(vertexId);

wExpectedProduction = 3.0;
wResourceNeed       = 1.5;
wDiversity          = 1.0;
wBlocking           = 0.2;
if isfield(config, 'heuristic')
    hw = config.heuristic;
    if isfield(hw, 'wExpectedProduction'), wExpectedProduction = hw.wExpectedProduction; end
    if isfield(hw, 'wResourceNeed'),       wResourceNeed       = hw.wResourceNeed;       end
    if isfield(hw, 'wDiversity'),          wDiversity          = hw.wDiversity;          end
    if isfield(hw, 'wBlocking'),           wBlocking           = hw.wBlocking;           end
end

expectedProduction = 0;
resourceNeedScore = 0;
producedTypes = false(1, numel(config.resourceNames));

for h = vertex.adjHexIds
    hex = state.board.hexes(h);
    p = catan_core('diceProbability', hex.diceNumber);
    rIdx = find(strcmp(config.resourceNames, hex.resourceType), 1);

    expectedProduction = expectedProduction + p;
    producedTypes(rIdx) = true;

    demand = config.buildCosts.settlement(rIdx);
    missing = max(demand - player.resources(rIdx), 0);
    resourceNeedScore = resourceNeedScore + p * missing;
end

existingProduced = currentCoverage(state, playerId, config);
newCoverageCount = sum(producedTypes & ~existingProduced);

neighbors = vertex.adjVertexIds;
blockingCount = 0;
for n = neighbors
    owner = state.board.vertices(n).owner;
    if owner ~= 0 && owner ~= playerId
        blockingCount = blockingCount + 1;
    end
end

score = 0;
score = score + wExpectedProduction * expectedProduction;
score = score + wResourceNeed * resourceNeedScore;
score = score + wDiversity * newCoverageCount;
score = score + wBlocking * blockingCount;
end

function coverage = currentCoverage(state, playerId, config)
coverage = false(1, numel(config.resourceNames));

for v = 1:numel(state.board.vertices)
    if state.board.vertices(v).owner ~= playerId
        continue;
    end

    for h = state.board.vertices(v).adjHexIds
        rIdx = find(strcmp(config.resourceNames, state.board.hexes(h).resourceType), 1);
        coverage(rIdx) = true;
    end
end
end
