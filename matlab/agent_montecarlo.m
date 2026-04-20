function action = agent_montecarlo(state, legalActions, playerId, config)
%AGENT_MONTECARLO  Flat Monte Carlo rollouts over legal actions.

% Count: Number of rollouts per action.
rolloutCount   = config.rolloutCount;
% Horizon: Number of turns to simulate after the current one.
rolloutHorizon = config.rolloutHorizon;

bestValue  = -inf;
bestAction = catan_core('makeAction', 'pass', 0);

for i = 1:numel(legalActions)
    candidate  = legalActions(i);
    totalValue = 0;

    parfor r = 1:rolloutCount
        rolloutState = catan_core('applyAction', state, playerId, candidate, config);
        rolloutState.placementPhase = false;

        [done, winnerId] = catan_core('checkTerminal', rolloutState, config);
        rolloutState.isTerminal = done;
        rolloutState.winnerId   = winnerId;

        % Finish current player's turn
        if ~rolloutState.isTerminal
            rolloutState = continueTurnWithPolicy(rolloutState, playerId, config.mc.selfRolloutPolicy, config);
        end

        if ~rolloutState.isTerminal
            rolloutState.currentPlayer = mod(playerId, config.numPlayers) + 1;
            rolloutState.turnIndex     = rolloutState.turnIndex + 1;
        end

        % Simulate forward
        for t = 1:rolloutHorizon
            if rolloutState.isTerminal, break; end

            cp = rolloutState.currentPlayer;

            % Roll and handle 7
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

            rolloutState = continueTurnWithPolicy(rolloutState, cp, policy, config);

            if ~rolloutState.isTerminal
                rolloutState.currentPlayer = mod(cp, config.numPlayers) + 1;
                rolloutState.turnIndex     = rolloutState.turnIndex + 1;
                [done, winnerId] = catan_core('checkTerminal', rolloutState, config);
                rolloutState.isTerminal = done;
                rolloutState.winnerId   = winnerId;
            end
        end

        totalValue = totalValue + rolloutUtility(rolloutState, playerId);
    end

    value = totalValue / rolloutCount;
    if value > bestValue
        bestValue  = value;
        bestAction = candidate;
    end
end

action = bestAction;
end

% =========================================================================

function state = continueTurnWithPolicy(state, playerId, policyName, config)
state.devCardPlayedThisTurn = false;

actionCap = 30;
for step = 1:actionCap
    legalActions = catan_core('enumerateLegalActions', state, playerId, config);
    action       = selectPolicyAction(policyName, state, legalActions, playerId, config);

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
