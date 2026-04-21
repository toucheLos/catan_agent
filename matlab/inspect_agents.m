function results = inspect_agents(state, playerId, config)
%INSPECT_AGENTS  Run all four agents on a frozen state as the same player.
%
%   results = inspect_agents(state, playerId, config)
%
%   Queries random, heuristic, monte_carlo, and mcts as playerId and prints
%   a formatted comparison table. Returns a struct array with fields:
%   agent (string) and action (struct).

agentNames = {'random', 'heuristic', 'monte_carlo', 'mcts'};
agentFns   = {@agent_random, @agent_heuristic, @agent_montecarlo, @agent_mcts};

legalActions = catan_core('enumerateLegalActions', state, playerId, config);

fprintf('\n========================================\n');
fprintf('  Agent Inspector | Player %d | Turn %d\n', playerId, state.turnIndex);
fprintf('  Legal actions: %d\n', numel(legalActions));
fprintf('========================================\n');
fprintf('  %-15s  %s\n', 'Agent', 'Chosen Action');
fprintf('  %s\n', repmat('-', 1, 44));

results = struct('agent', agentNames, 'action', cell(1, 4));
for i = 1:4
    a = agentFns{i}(state, legalActions, playerId, config);
    results(i).action = a;
    fprintf('  %-15s  %s\n', agentNames{i}, formatAction(a));
end
fprintf('========================================\n\n');
end

function s = formatAction(a)
switch a.type
    case 'pass',               s = 'pass';
    case 'build_settlement',   s = sprintf('build_settlement   v=%d', a.vertexId);
    case 'build_road',         s = sprintf('build_road         e=%d', a.edgeId);
    case 'build_city',         s = sprintf('build_city         v=%d', a.vertexId);
    case 'buy_dev_card',       s = 'buy_dev_card';
    case 'maritime_trade',     s = sprintf('trade  %s → %s', a.resourceType, a.resource2);
    case 'move_robber',        s = sprintf('move_robber        h=%d  steal p%d', a.hexId, a.targetPlayer);
    case 'play_knight',        s = sprintf('play_knight        h=%d  steal p%d', a.hexId, a.targetPlayer);
    case 'play_road_building', s = 'play_road_building';
    case 'play_year_of_plenty',s = sprintf('year_of_plenty     %s + %s', a.resourceType, a.resource2);
    case 'play_monopoly',      s = sprintf('play_monopoly      %s', a.resourceType);
    otherwise,                 s = a.type;
end
end
