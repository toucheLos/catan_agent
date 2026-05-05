function action = agent_montecarlo(state, legalActions, playerId, config)
%AGENT_MONTECARLO  Flat Monte Carlo rollouts over legal actions.

rolloutCount = config.rolloutCount;
rolloutHorizon = config.rolloutHorizon;

bestValue = -inf;
bestAction = catan_core('makeAction', 'pass', 0);

for i = 1:numel(legalActions)
    candidate = legalActions(i);
    vals = zeros(1, rolloutCount);

    parfor r = 1:rolloutCount
        s = catan_core('applyAction', state, playerId, candidate, config);
        s.placementPhase = false;

        [done, wId] = catan_core('checkTerminal', s, config);
        s.isTerminal = done; s.winnerId = wId;

        if ~s.isTerminal
            s = carlo_help('applypolicy', s, playerId, config.mc.selfRolloutPolicy, config);
        end
        if ~s.isTerminal
            s.currentPlayer = mod(playerId, config.numPlayers) + 1;
            s.turnIndex = s.turnIndex + 1;
        end

        for t = 1:rolloutHorizon
            if s.isTerminal, break; end
            cp = s.currentPlayer;
            roll = catan_core('rollDice');
            s.lastRoll = roll;
            if roll == 7
                s = catan_core('autoRobber', s, cp, config);
            else
                s = catan_core('distributeResources', s, roll, config);
            end
            s.devCardPlayedThisTurn = false;
            if cp == playerId
                policy = config.mc.selfRolloutPolicy;
            else
                policy = config.mc.opponentRolloutPolicy;
            end
            s = carlo_help('applypolicy', s, cp, policy, config);
            if ~s.isTerminal
                s.currentPlayer = mod(cp, config.numPlayers) + 1;
                s.turnIndex = s.turnIndex + 1;
                [done, wId]  = catan_core('checkTerminal', s, config);
                s.isTerminal = done; s.winnerId = wId;
            end
        end

        vals(r) = carlo_help('rolloututility', s, playerId, 0.25);
    end

    value = sum(vals) / rolloutCount;
    if value > bestValue
        bestValue  = value;
        bestAction = candidate;
    end
end

action = bestAction;
end
