function action = agent_mcts(state, legalActions, playerId, config)
%AGENT_MCTS  One-level Monte Carlo Tree Search with UCB1 action selection.
%
% Each legal action is a child of the root node. UCB1 balances exploitation
% (high average rollout utility) with exploration (rarely tried actions).
% After the budget is exhausted, picks the action with the highest average.
%
% Key config fields:
%   config.rolloutCount    — total rollouts per action (budget = count * numActions)
%   config.rolloutHorizon  — max simulated turns per rollout
%   config.mcts.C          — UCB1 exploration constant (default sqrt(2))
%   config.mc.selfRolloutPolicy     — policy for self during rollouts
%   config.mc.opponentRolloutPolicy — policy for opponents during rollouts

numActions = numel(legalActions);

% Trivial case: only one choice.
if numActions == 1
    action = legalActions(1);
    return;
end

% Read exploration constant from config (default sqrt(2)).
C = sqrt(2);
if isfield(config, 'mcts') && isfield(config.mcts, 'C')
    C = config.mcts.C;
end

rolloutHorizon = config.rolloutHorizon;
totalBudget    = config.rolloutCount * numActions;

visitCounts = zeros(1, numActions);
totalValues = zeros(1, numActions);

% Seed phase: one rollout per action so UCB1 never divides by zero.
for i = 1:numActions
    totalValues(i) = mctsRollout(state, legalActions(i), playerId, rolloutHorizon, config);
    visitCounts(i) = 1;
end
totalVisits     = numActions;
remainingBudget = totalBudget - numActions;

% UCB1 selection loop.
for iter = 1:remainingBudget
    % UCB1: argmax [ Q(a) + C * sqrt( ln(N) / n(a) ) ]
    ucbScores = (totalValues ./ visitCounts) + C * sqrt(log(totalVisits) ./ visitCounts);
    [~, idx]  = max(ucbScores);

    v                  = mctsRollout(state, legalActions(idx), playerId, rolloutHorizon, config);
    visitCounts(idx)   = visitCounts(idx)   + 1;
    totalValues(idx)   = totalValues(idx)   + v;
    totalVisits        = totalVisits        + 1;
end

% Return action with highest average rollout value.
[~, bestIdx] = max(totalValues ./ visitCounts);
action = legalActions(bestIdx);

end

% =========================================================================
%  Rollout helpers  (mirrors agent_montecarlo.m internals)
% =========================================================================

function u = mctsRollout(state, candidate, playerId, rolloutHorizon, config)
%MCTSROLLOUT  Simulate one rollout starting from candidate action and return utility.

rolloutState = catan_core('applyAction', state, playerId, candidate, config);

[done, winnerId]        = catan_core('checkTerminal', rolloutState, config);
rolloutState.isTerminal = done;
rolloutState.winnerId   = winnerId;

% Finish the current player's turn using the self-rollout policy.
if ~rolloutState.isTerminal && strcmp(candidate.type, 'build_settlement')
    rolloutState = mctsApplyPolicy(rolloutState, playerId, config.mc.selfRolloutPolicy, config);
end

% Advance to next player.
if ~rolloutState.isTerminal
    rolloutState.currentPlayer = mod(playerId, config.numPlayers) + 1;
    rolloutState.turnIndex     = rolloutState.turnIndex + 1;
end

% Simulate forward for rolloutHorizon turns.
for t = 1:rolloutHorizon
    if rolloutState.isTerminal
        break;
    end

    cp                  = rolloutState.currentPlayer;
    rolloutState.lastRoll = catan_core('rollDice');
    rolloutState        = catan_core('distributeResources', rolloutState, rolloutState.lastRoll, config);

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
%MCTSAPPLYPOLICY  Apply a named rollout policy until the player passes or game ends.

actionCap = numel(state.board.vertices) + 1;
for step = 1:actionCap
    legalActions = catan_core('enumerateLegalActions', state, playerId, config);
    action       = mctsPolicySelect(policyName, state, legalActions, playerId, config);
    state        = catan_core('applyAction', state, playerId, action, config);

    [done, winnerId]    = catan_core('checkTerminal', state, config);
    state.isTerminal    = done;
    state.winnerId      = winnerId;

    if done || ~strcmp(action.type, 'build_settlement')
        return;
    end
end
end

function action = mctsPolicySelect(policyName, state, legalActions, playerId, config)
%MCTSPOLICYSELECT  Pick an action using the named policy.

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
%MCTSUTILITY  Win/loss bonus + scaled VP lead (same formula as agent_montecarlo).

myVP   = state.players(rootPlayer).victoryPoints;
allVP  = [state.players.victoryPoints];
oppIdx = setdiff(1:numel(allVP), rootPlayer);
if isempty(oppIdx)
    maxOppVP = myVP;
else
    maxOppVP = max(allVP(oppIdx));
end

vpLead   = myVP - maxOppVP;
winBonus = 0;
if state.isTerminal
    if     state.winnerId == rootPlayer, winBonus =  1.0;
    elseif state.winnerId ~= 0,          winBonus = -1.0;
    end
end

u = winBonus + 0.10 * vpLead;
end
