function action = agent_mcts(state, legalActions, playerId, config)
%AGENT_MCTS  One-level Monte Carlo Tree Search with UCB1 action selection.
%
%  config.mcts.C     — UCB1 exploration constant (default sqrt(3))
%  config.mcts.depth — heuristic-guided turns before flat random rollout (default 5)

numActions = numel(legalActions);
if numActions == 1, action = legalActions(1); return; end

C = config.mcts.C;
depth = config.mcts.depth;

totalBudget = config.rolloutCount * numActions;
visitCounts = zeros(1, numActions);
totalValues = zeros(1, numActions);

% Seed: one rollout per action
parfor i = 1:numActions
    totalValues(i) = mctsDeepRollout(state, legalActions(i), playerId, playerId, depth, config.rolloutHorizon, config);
    visitCounts(i) = 1;
end
totalVisits     = numActions;
remainingBudget = totalBudget - numActions;

% UCB1 selection
for iter = 1:remainingBudget
    ucbScores = (totalValues ./ visitCounts) + C * sqrt(log(totalVisits) ./ visitCounts);
    [~, idx]  = max(ucbScores);
    v                = mctsDeepRollout(state, legalActions(idx), playerId, playerId, depth, config.rolloutHorizon, config);
    visitCounts(idx) = visitCounts(idx) + 1;
    totalValues(idx) = totalValues(idx) + v;
    totalVisits      = totalVisits + 1;
end

[~, bestIdx] = max(totalValues ./ visitCounts);
action = legalActions(bestIdx);
end

% =========================================================================

function u = mctsDeepRollout(state, candidate, actingPlayer, rootPlayer, depth, rolloutHorizon, config)
state = catan_core('applyAction', state, actingPlayer, candidate, config);
state.placementPhase = false;

[done, wId] = catan_core('checkTerminal', state, config);
state.isTerminal = done; state.winnerId = wId;

if ~state.isTerminal
    state = carlo_help('applypolicy', state, actingPlayer, config.mc.selfRolloutPolicy, config);
end
if state.isTerminal
    u = carlo_help('rolloututility', state, rootPlayer, 0.50); return;
end

state.currentPlayer = mod(actingPlayer, config.numPlayers) + 1;
state.turnIndex     = state.turnIndex + 1;

for d = 1:depth
    if state.isTerminal, break; end
    cp    = state.currentPlayer;
    state = catan_core('advanceDevCards', state, cp);
    roll  = catan_core('rollDice');
    state.lastRoll = roll;
    if roll == 7
        state = catan_core('autoRobber', state, cp, config);
    else
        state = catan_core('distributeResources', state, roll, config);
    end
    state.devCardPlayedThisTurn = false;
    if cp == rootPlayer
        policy = config.mc.selfRolloutPolicy;
    else
        policy = config.mc.opponentRolloutPolicy;
    end
    state = carlo_help('applypolicy', state, cp, policy, config);
    if ~state.isTerminal
        state.currentPlayer = mod(cp, config.numPlayers) + 1;
        state.turnIndex     = state.turnIndex + 1;
        [done, wId]      = catan_core('checkTerminal', state, config);
        state.isTerminal = done; state.winnerId = wId;
    end
end

for t = 1:(rolloutHorizon - depth)
    if state.isTerminal, break; end
    cp = state.currentPlayer;
    state = catan_core('advanceDevCards', state, cp);
    roll = catan_core('rollDice');
    state.lastRoll = roll;
    if roll == 7
        state = catan_core('autoRobber', state, cp, config);
    else
        state = catan_core('distributeResources', state, roll, config);
    end
    state.devCardPlayedThisTurn = false;
    state = carlo_help('applypolicy', state, cp, 'random', config);
    if ~state.isTerminal
        state.currentPlayer = mod(cp, config.numPlayers) + 1;
        state.turnIndex     = state.turnIndex + 1;
        [done, wId]      = catan_core('checkTerminal', state, config);
        state.isTerminal = done; state.winnerId = wId;
    end
end

u = carlo_help('rolloututility', state, rootPlayer, 0.50);
end
