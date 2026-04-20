function action = agent_mcts(state, legalActions, playerId, config)
%AGENT_MCTS  One-level Monte Carlo Tree Search with UCB1 action selection.
%
%  config.mcts.C     — UCB1 exploration constant (default sqrt(2))
%  config.mcts.depth — number of full turns simulated with heuristic/policy
%                      before switching to flat random rollout (default 2)

numActions = numel(legalActions);
if numActions == 1
    action = legalActions(1); return;
end

C = sqrt(2);
if isfield(config,'mcts') && isfield(config.mcts,'C'), C = config.mcts.C; end

depth          = 2;
if isfield(config,'mcts') && isfield(config.mcts,'depth'), depth = config.mcts.depth; end

rolloutHorizon = config.rolloutHorizon;
totalBudget    = config.rolloutCount * numActions;

visitCounts = zeros(1, numActions);
totalValues = zeros(1, numActions);

% Seed: one rollout per action
parfor i = 1:numActions
    totalValues(i) = mctsDeepRollout(state, legalActions(i), playerId, playerId, depth, rolloutHorizon, config);
    visitCounts(i) = 1;
end
totalVisits     = numActions;
remainingBudget = totalBudget - numActions;

% UCB1 selection
for iter = 1:remainingBudget
    ucbScores = (totalValues ./ visitCounts) + C * sqrt(log(totalVisits) ./ visitCounts);
    [~, idx]  = max(ucbScores);
    v                = mctsDeepRollout(state, legalActions(idx), playerId, playerId, depth, rolloutHorizon, config);
    visitCounts(idx) = visitCounts(idx) + 1;
    totalValues(idx) = totalValues(idx) + v;
    totalVisits      = totalVisits + 1;
end

[~, bestIdx] = max(totalValues ./ visitCounts);
action = legalActions(bestIdx);
end

% =========================================================================

function u = mctsDeepRollout(state, candidate, actingPlayer, rootPlayer, depth, rolloutHorizon, config)
% Apply candidate action, finish actingPlayers turn, then simulate 'depth'
% full turns with heuristic/policy before falling through to flat rollout.

state = catan_core('applyAction', state, actingPlayer, candidate, config);
state.placementPhase = false;

[done, winnerId]   = catan_core('checkTerminal', state, config);
state.isTerminal   = done;
state.winnerId     = winnerId;

if ~state.isTerminal
    state = mctsApplyPolicy(state, actingPlayer, config.mc.selfRolloutPolicy, config);
end

if state.isTerminal
    u = mctsUtility(state, rootPlayer);
    return;
end

% Advance to next player
state.currentPlayer = mod(actingPlayer, config.numPlayers) + 1;
state.turnIndex     = state.turnIndex + 1;

% Simulate `depth` full turns with heuristic/policy before flat rollout
for d = 1:depth
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

    if cp == rootPlayer
        policy = config.mc.selfRolloutPolicy;
    else
        policy = config.mc.opponentRolloutPolicy;
    end

    state = mctsApplyPolicy(state, cp, policy, config);

    if ~state.isTerminal
        state.currentPlayer = mod(cp, config.numPlayers) + 1;
        state.turnIndex     = state.turnIndex + 1;
        [done, winnerId]    = catan_core('checkTerminal', state, config);
        state.isTerminal    = done;
        state.winnerId      = winnerId;
    end
end

% Flat rollout for remaining horizon
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
    state = mctsApplyPolicy(state, cp, 'random', config);

    if ~state.isTerminal
        state.currentPlayer = mod(cp, config.numPlayers) + 1;
        state.turnIndex     = state.turnIndex + 1;
        [done, winnerId]    = catan_core('checkTerminal', state, config);
        state.isTerminal    = done;
        state.winnerId      = winnerId;
    end
end

u = mctsUtility(state, rootPlayer);
end

% =========================================================================

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
    if state.winnerId == rootPlayer, winBonus =  1.0;
    elseif state.winnerId ~= 0,          winBonus = -1.0;
    end
end
u = winBonus + 0.50 * vpLead;
end
