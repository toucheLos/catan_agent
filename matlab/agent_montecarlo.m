open agenfunction action = agent_montecarlo(state, legalActions, playerId, config)
%AGENT_MONTECARLO Flat Monte Carlo rollouts over legal actions.

rolloutCount = config.rolloutCount;
rolloutHorizon = config.rolloutHorizon;

bestValue = -inf;
bestAction = catan_core('makeAction', 'pass', 0);

for i = 1:numel(legalActions)
    candidate = legalActions(i);
    totalValue = 0;

    for r = 1:rolloutCount
        rolloutState = state;
        rolloutState = catan_core('applyAction', rolloutState, playerId, candidate, config);

        [done, winnerId] = catan_core('checkTerminal', rolloutState, config);
        rolloutState.isTerminal = done;
        rolloutState.winnerId = winnerId;

        if ~rolloutState.isTerminal && strcmp(candidate.type, 'build_settlement')
            rolloutState = continueTurnWithPolicy(rolloutState, playerId, config.mc.selfRolloutPolicy, config);
        end

        if ~rolloutState.isTerminal
            rolloutState.currentPlayer = mod(playerId, config.numPlayers) + 1;
            rolloutState.turnIndex = rolloutState.turnIndex + 1;
        end

        for t = 1:rolloutHorizon
            if rolloutState.isTerminal
                break;
            end

            cp = rolloutState.currentPlayer;
            rolloutState.lastRoll = catan_core('rollDice');
            rolloutState = catan_core('distributeResources', rolloutState, rolloutState.lastRoll, config);

            if cp == playerId
                policy = config.mc.selfRolloutPolicy;
            else
                policy = config.mc.opponentRolloutPolicy;
            end

            rolloutState = continueTurnWithPolicy(rolloutState, cp, policy, config);

            if ~rolloutState.isTerminal
                rolloutState.currentPlayer = mod(cp, config.numPlayers) + 1;
                rolloutState.turnIndex = rolloutState.turnIndex + 1;
                [done, winnerId] = catan_core('checkTerminal', rolloutState, config);
                rolloutState.isTerminal = done;
                rolloutState.winnerId = winnerId;
            end
        end

        totalValue = totalValue + rolloutUtility(rolloutState, playerId);
    end

    value = totalValue / rolloutCount;
    if value > bestValue
        bestValue = value;
        bestAction = candidate;
    end
end

action = bestAction;

end

function state = continueTurnWithPolicy(state, playerId, policyName, config)
actionCap = numel(state.board.vertices) + 1;
for step = 1:actionCap
    legalActions = catan_core('enumerateLegalActions', state, playerId, config);
    action = selectPolicyAction(policyName, state, legalActions, playerId, config);
    state = catan_core('applyAction', state, playerId, action, config);

    [done, winnerId] = catan_core('checkTerminal', state, config);
    state.isTerminal = done;
    state.winnerId = winnerId;

    if done || ~strcmp(action.type, 'build_settlement')
        return;
    end
end
end

function action = selectPolicyAction(policyName, state, legalActions, playerId, config)
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

function u = rolloutUtility(state, rootPlayer)
myVP = state.players(rootPlayer).victoryPoints;
allVP = [state.players.victoryPoints];
oppIdx = setdiff(1:numel(allVP), rootPlayer);
if isempty(oppIdx)
    maxOppVP = myVP;
else
    maxOppVP = max(allVP(oppIdx));
end
vpLead = myVP - maxOppVP;

winBonus = 0;
if state.isTerminal
    if state.winnerId == rootPlayer
        winBonus = 1.0;
    elseif state.winnerId ~= 0
        winBonus = -1.0;
    end
end

u = winBonus + 0.10 * vpLead;
end
