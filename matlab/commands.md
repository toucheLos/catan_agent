catan_core — Game Engine

  Run a game (interactive entry point)

  catan_core
  % Edit the PARAMS block inside runGame() to change players/settings

  defaultConfig — get config struct

  config = catan_core('defaultConfig')

  simulateGame — run a full game

  config = catan_core('defaultConfig');
  config.showViz = false;
  config.verbose = false;
  config.rngSeed = 42;

  agentFns = {@agent_random, @agent_heuristic, @agent_mcts};
  history  = catan_core('simulateGame', agentFns, config, {'random','heuristic','mcts'})
  % history.finalState, history.actions, history.logs

  enumerateLegalActions — get legal moves for a player

  legal = catan_core('enumerateLegalActions', state, playerId, config)

  applyAction — apply a move, get new state

  state = catan_core('applyAction', state, playerId, action, config)

  checkTerminal — is the game over?

  [done, winnerId] = catan_core('checkTerminal', state, config)

  distributeResources — hand out resources for a dice roll

  state = catan_core('distributeResources', state, roll, config)

  rollDice — roll 2d6

  roll = catan_core('rollDice')

  makeAction — construct an action struct

  % Signature: makeAction(type, vertexId, edgeId, hexId, targetPlayer, resourceType,
  resource2)
  action = catan_core('makeAction', 'build_settlement', 14, 0, 0, 0, '', '')
  action = catan_core('makeAction', 'build_road',       0, 7,  0, 0, '', '')
  action = catan_core('makeAction', 'build_city',       14, 0, 0, 0, '', '')
  action = catan_core('makeAction', 'buy_dev_card',     0,  0, 0, 0, '', '')
  action = catan_core('makeAction', 'maritime_trade',   0,  0, 0, 0, 'wood', 'ore')
  action = catan_core('makeAction', 'move_robber',      0,  0, 5, 2, '', '')   % hex 5,
  steal from P2
  action = catan_core('makeAction', 'play_knight',      0,  0, 5, 2, '', '')
  action = catan_core('makeAction', 'play_road_building',0, 0, 0, 0, '', '')
  action = catan_core('makeAction', 'play_year_of_plenty',0,0, 0, 0, 'wheat', 'ore')
  action = catan_core('makeAction', 'play_monopoly',    0,  0, 0, 0, 'sheep', '')
  action = catan_core('makeAction', 'pass',             0,  0, 0, 0, '', '')

  isLegalAction — validate an action against a legal list

  tf = catan_core('isLegalAction', action, legalActions)

  diceProbability — probability of rolling n

  p = catan_core('diceProbability', 6)   % p = 5/36
  p = catan_core('diceProbability', 7)   % p = 6/36

  computeVP — get a player's current victory points

  vp = catan_core('computeVP', state, playerId)

  autoRobber — auto-resolve robber when a 7 is rolled

  state = catan_core('autoRobber', state, playerId, config)

  advanceDevCards — make newly bought dev cards playable

  state = catan_core('advanceDevCards', state, playerId)

  enumerateRobberActions — legal robber placements for a player

  robberActions = catan_core('enumerateRobberActions', state, playerId, config)

  ---
  tournament — Experiment Runner

  tournament()        % all agent combos at 2/3/4 players, 50 games/matchup
  tournament(10)      % same but 10 games/matchup (faster)
  tournament(100)     % more games for statistical confidence

  ---
  Typical multi-line workflows

  Inspect a specific game state

  config   = catan_core('defaultConfig');
  config.showViz = false; config.verbose = false;
  agentFns = {@agent_heuristic, @agent_random};
  history  = catan_core('simulateGame', agentFns, config);
  fs       = history.finalState;

  for p = 1:2
      fprintf('P%d VP: %d\n', p, catan_core('computeVP', fs, p));
  end
  fprintf('Winner: P%d | Turns: %d\n', fs.winnerId, fs.turnIndex);

  Step through legal actions manually

  config   = catan_core('defaultConfig');
  config.showViz = false;
  agentFns = {@agent_random, @agent_random};
  history  = catan_core('simulateGame', agentFns, config);
  state    = history.finalState;

  legal = catan_core('enumerateLegalActions', state, 1, config);
  disp({legal.type}')                  % see all action types available
  [done, w] = catan_core('checkTerminal', state, config)

  Run a quick 2-agent head-to-head

  config = catan_core('defaultConfig');
  config.showViz = false; config.verbose = false; config.rngSeed = 99;
  history = catan_core('simulateGame', {@agent_mcts, @agent_heuristic}, config,{'mcts','heuristic'});
  fprintf('Winner: %s\n', history.finalState.winnerId);