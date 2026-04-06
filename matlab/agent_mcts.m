function action = agent_mcts(state, legalActions, playerId, config)
%AGENT_MCTS  One-level Monte Carlo Tree Search with UCB1 action selection.

numActions = numel(legalActions);
if numActions == 1
    action = legalActions(1); return;
end

C = sqrt(2);
if isfield(config,'mcts') && isfield(config.mcts,'C'), C = config.mcts.C; end

rolloutHorizon = config.rolloutHorizon;
totalBudget    = config.rolloutCount * numActions;

visitCounts = zeros(1, numActions);
totalValues = zeros(1, numActions);

% Seed: one rollout per action
for i = 1:numActions
    totalValues(i) = mctsRollout(state, legalActions(i), playerId, rolloutHorizon, config);
    visitCounts(i) = 1;
end
totalVisits     = numActions;
remainingBudget = totalBudget - numActions;

% UCB1 selection
for iter = 1:remainingBudget
    ucbScores = (totalValues ./ visitCounts) + C * sqrt(log(totalVisits) ./ visitCounts);
    [~, idx]  = max(ucbScores);
    v                = mctsRollout(state, legalActions(idx), playerId, rolloutHorizon, config);
    visitCounts(idx) = visitCounts(idx) + 1;
    totalValues(idx) = totalValues(idx) + v;
    totalVisits      = totalVisits + 1;
end

[~, bestIdx] = max(totalValues ./ visitCounts);
action = legalActions(bestIdx);
end

% =========================================================================

function u = mctsRollout(state, candidate, playerId, rolloutHorizon, config)
rolloutState = catan_core('applyAction', state, playerId, candidate, config);

[done, winnerId]        = catan_core('checkTerminal', rolloutState, config);
rolloutState.isTerminal = done;
rolloutState.winnerId   = winnerId;

if ~rolloutState.isTerminal
    rolloutState = mctsApplyPolicy(rolloutState, playerId, config.mc.selfRolloutPolicy, config);
end

if ~rolloutState.isTerminal
    rolloutState.currentPlayer = mod(playerId, config.numPlayers) + 1;
    rolloutState.turnIndex     = rolloutState.turnIndex + 1;
end

for t = 1:rolloutHorizon
    if rolloutState.isTerminal, break; end

    cp = rolloutState.currentPlayer;

    roll = catan_core('rollDice');
    rolloutState.lastRoll = roll;
    if roll == 7
        rolloutState = catan_core('autoRobber', rolloutState, cp, config);
    else
        rolloutState = catan_core('distributeResources', rolloutState, roll, config);
    end

    rolloutState.devCardPlayedThisTurn = false;

    if cp == playerId
        policy = config.mc.selfRolloutPolicy;
    else
        policy = config.mc.opponentRolloutPolicy;
    end

    rolloutState = mctsApplyPolicy(rolloutState, cp, policy, config);

    if ~rolloutState.isTerminal
        rolloutState.currentPlayer = mod(cp, config.numPlayers) + 1;
        rolloutState.turnIndex     = rolloutState.turnIndex + 1;
        [done, winnerId]        = catan_core('checkTerminal', rolloutState, config);
        rolloutState.isTerminal = done;
        rolloutState.winnerId   = winnerId;
    end
end

u = mctsUtility(rolloutState, playerId);
end

function state = mctsApplyPolicy(state, playerId, policyName, config)
state.devCardPlayedThisTurn = false;
actionCap = 30;
for step = 1:actionCap
    legalActions = catan_core('enumerateLegalActions', state, playerId, config);
    action       = mctsPolicySelect(policyName, state, legalActions, playerId, config);

    if strcmp(action.type,'pass') && state.freeRoads == 0
        return;
    end

    state = catan_core('applyAction', state, playerId, action, config);

    [done, winnerId] = catan_core('checkTerminal', state, config);
    state.isTerminal = done;
    state.winnerId   = winnerId;
    if done, return; end
end
end

function action = mctsPolicySelect(policyName, state, legalActions, playerId, config)
switch lower(policyName)
    case 'heuristic'
        action = agent_heuristic(state, legalActions, playerId, config);
    otherwise
        action = agent_random(state, legalActions, playerId, config);
end
if ~catan_core('isLegalAction', action, legalActions)
    action = catan_core('makeAction', 'pass', 0);
end
end

function u = mctsUtility(state, rootPlayer)
myVP   = state.players(rootPlayer).victoryPoints;
allVP  = [state.players.victoryPoints];
oppIdx = setdiff(1:numel(allVP), rootPlayer);
maxOppVP = isempty(oppIdx) * myVP + ~isempty(oppIdx) * max(allVP(oppIdx));
vpLead   = myVP - maxOppVP;
winBonus = 0;
if state.isTerminal
    if     state.winnerId == rootPlayer, winBonus =  1.0;
    elseif state.winnerId ~= 0,          winBonus = -1.0;
    end
end
u = winBonus + 0.10 * vpLead;
end
