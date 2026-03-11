# MATLAB Catan Agent

A simplified Settlers of Catan simulation engine written in MATLAB. The game focuses on settlement placement as the core mechanic. Supports automated agents (random, heuristic, Monte Carlo) and a live interactive player.

## File Structure

```
matlab/
  catan_core.m       — game engine, game loop, and live player (single file)
  agent_random.m     — random policy agent
  agent_heuristic.m  — heuristic scoring agent
  agent_montecarlo.m — Monte Carlo rollout agent
```

---

## Quick Start

Open MATLAB, `cd` into the `matlab/` folder, and run:

```matlab
catan_core
```

That's it. The game starts immediately using the parameters defined in `runGame()` inside `catan_core.m`.

To change who plays, edit the `PARAMS.players` line near the top of `runGame()`:

```matlab
PARAMS.players = {'random', 'heuristic'};         % two AI players
PARAMS.players = {'heuristic', 'monte_carlo'};    % different AI matchup
PARAMS.players = {'random', 'heuristic', 'live'}; % you vs two AIs
```

Player type options: `'random'`, `'heuristic'`, `'monte_carlo'`, `'mcts'`, `'live'`

---

## Parameters

All tunable parameters live in the `PARAMS` block at the top of `runGame()` in `catan_core.m`:

| Parameter | Default | Description |
|---|---|---|
| `PARAMS.players` | `{'random','heuristic'}` | Players in turn order |
| `PARAMS.pauseAfterMove` | `true` | Pause after each AI move (press Enter to advance) |
| `PARAMS.rngSeed` | `42` | RNG seed; set to `0` for a random board each run |
| `PARAMS.winSettlements` | `8` | Settlements needed to win |
| `PARAMS.maxTurns` | `200` | Turn cap to prevent infinite games |
| `PARAMS.mc.rolloutCount` | `20` | Monte Carlo rollouts per candidate action |
| `PARAMS.mc.rolloutHorizon` | `30` | Max turns simulated per rollout |
| `PARAMS.mc.selfRolloutPolicy` | `'heuristic'` | Policy used for self during MC rollouts |
| `PARAMS.mc.opponentRolloutPolicy` | `'random'` | Policy used for opponents during MC rollouts |
| `config.heuristic.wExpectedProduction` | `3.0` | Heuristic weight: expected dice production |
| `config.heuristic.wResourceNeed` | `1.5` | Heuristic weight: shortage of needed resources |
| `config.heuristic.wDiversity` | `1.0` | Heuristic weight: new resource types unlocked |
| `config.heuristic.wBlocking` | `0.2` | Heuristic weight: adjacent opponent settlements |
| `config.mcts.C` | `sqrt(2)` | MCTS UCB1 exploration constant |

---

## Advanced Usage

You can also call specific engine commands directly:

```matlab
% Get the default config struct.
config = catan_core('defaultConfig');

% Run a game programmatically with custom agents.
agents  = {@agent_random, @agent_heuristic, @agent_montecarlo};
history = catan_core('simulateGame', agents, config);

% Inspect the result.
history.finalState.winnerId
history.logs
history.actions
```

### Running a Tournament

```matlab
% Baseline: 50 games per matchup, all four agent types.
results = catan_core('runTournament', {'random', 'heuristic', 'monte_carlo', 'mcts'}, 50);

% Quick check with just two agents.
results = catan_core('runTournament', {'random', 'heuristic'}, 100);

% Use a custom config (e.g. change win threshold).
cfg = catan_core('defaultConfig');
cfg.winSettlements = 6;
results = catan_core('runTournament', {'heuristic', 'mcts'}, 30, cfg);
```

The tournament suppresses per-turn output automatically and produces:
- A console table of P1-win-rates for every ordered matchup pair
- A bar chart of overall win rates (P1 + P2 combined)
- A heat map of the win-rate matrix

### Tuning the Heuristic Agent

```matlab
cfg = catan_core('defaultConfig');
cfg.heuristic.wExpectedProduction = 5.0;  % emphasise high-probability spots
cfg.heuristic.wBlocking           = 0.8;  % more aggressive blocking
history = catan_core('simulateGame', {@agent_heuristic, @agent_random}, cfg);
```

---

## Functions Reference

### `catan_core.m` — Engine + Entry Point

#### `catan_core` (entry point dispatcher)
The top-level function. When called with no arguments (`catan_core`), it immediately starts a game using the parameters in `runGame()`. When called with a command string, it dispatches to the appropriate internal function. This single-file design keeps the entire engine self-contained.

#### `runGame()`
**The main entry point.** Contains the `PARAMS` block where you configure players, win conditions, turn limits, and Monte Carlo settings. Maps player-type strings (`'random'`, `'heuristic'`, `'monte_carlo'`, `'live'`) to agent function handles, then calls `simulateGame` and prints a final summary.

#### `defaultConfig()`
Returns a `config` struct with all default engine parameters. You can modify the returned struct before passing it to `simulateGame`. Fields include `numPlayers`, `maxTurns`, `winSettlements`, `resourceNames`, `buildCosts`, `initialResources`, `initialFreeSettlements`, `enforceDistanceRule`, `rngSeed`, `pauseAfterMove`, and Monte Carlo settings.

#### `simulateGame(agentFns, config, playerNames)`
Runs one complete game from start to finish. Handles the free placement phase, then loops: roll dice → distribute resources → ask agent for action → apply action → check terminal. Returns a `history` struct containing `logs` (human-readable strings), `actions` (machine-readable records), and `finalState`. Pauses after each AI move when `config.pauseAfterMove` is true.

#### `initGame(config)`
Creates the initial game state: seeds the RNG, builds the board, initializes the player array (resources, settlement count, VP), and sets counters (turn index, current player, terminal flag).

#### `initialPlacement(state, agentFns, config, playerNames, doPause)`
Runs the free settlement placement phase before the main game loop. Each player places `config.initialFreeSettlements` settlements at no resource cost, in round-robin order. Settlements placed here are what generate resources during the game.

#### `enumerateLegalActionsFree(state, config)`
Returns all legal placement actions for the initial placement phase. Unlike normal turns, there is no resource cost check — only the distance rule and ownership are enforced. Always includes a `pass` action.

#### `applyActionFree(state, playerId, action, config)`
Applies a free settlement placement to the state. Claims a vertex for the player, increments their settlement count and VP. No resources are deducted.

#### `rollDice()`
Simulates rolling two standard six-sided dice and returns the sum (2–12). Uses MATLAB's `randi`.

#### `distributeResources(state, roll, config)`
For every owned settlement, checks each adjacent hex. If a hex's dice number matches the roll and the hex is not desert, the settlement's owner receives +1 of that resource. This runs for all players simultaneously each turn.

#### `enumerateLegalActions(state, playerId, config)`
Returns the list of legal actions for a player on their normal turn. Always includes `pass`. Includes `build_settlement` actions for every unoccupied vertex the player can afford that does not violate the distance rule.

#### `applyAction(state, playerId, action, config)`
Applies a normal turn action. For `pass`, does nothing. For `build_settlement`, validates the vertex (bounds, ownership, distance rule, affordability), deducts the resource cost, claims the vertex, and updates settlement count and VP.

#### `checkTerminal(state, config)`
Checks whether the game is over. Returns `done=true` and the winning player ID if any player has reached `config.winSettlements`, or if `config.maxTurns` has been exceeded (winner is whoever has the most VP at that point).

#### `makeAction(type, vertexId)`
Constructs an action struct with fields `type` (string) and `vertexId` (integer). Used by agents and the engine to represent moves. Pass actions use `vertexId = 0`.

#### `isLegalAction(action, legalActions)`
Returns `true` if the given action exactly matches any entry in the `legalActions` array (matching both `type` and `vertexId`). Used to validate agent responses.

#### `diceProbability(n)`
Returns the probability that two d6 dice sum to `n`. Probabilities range from 1/36 (for 2 and 12) to 6/36 (for 7). Returns 0 for values outside 2–12.

#### `canAfford(resources, cost)`
Returns `true` if every element of `resources` is greater than or equal to the corresponding element of `cost`. Used before build actions.

#### `resourceIndex(resourceType, resourceNames)`
Maps a resource name string (e.g., `'wood'`) to its integer column index in the resource vector (1–5). Throws an error if the name is unrecognized.

#### `printPlayerResources(state, playerId, config)`
Prints a player's current resource counts and VP to the MATLAB console. Called at the start of each turn for display.

#### `agent_live(state, legalActions, playerId, config)`
The interactive human player agent. Displays current resources, VP, and a numbered list of legal actions. Waits for the user to type a number and press Enter. Validates input and re-prompts on invalid entries.

---

### Visualization (`catan_core.m`)

The visualization opens a 1300×740 window split into two panels that update live after every move. Set `PARAMS.showViz = false` to disable for batch runs.

#### `initGameFig(state, config, playerNames)`
Creates the game window with two axes tagged `'board'` (left 62%) and `'info'` (right 35%). Renders the initial empty board and calls `drawnow`. Returns the figure handle used for all subsequent updates.

#### `updateGameFig(fig, state, config, playerNames, currentPlayerId, actionStr, rollNum)`
Clears and redraws both axes with the current game state. Checks `ishandle(fig)` first so the simulation continues cleanly if the user closes the window. Called after every placement and every main-game action.

#### `highlightLegalActions(fig, legalActions, state)`
Overlays yellow rings on every vertex that is a legal `build_settlement` target. Called just before the live player is prompted for input so they can cross-reference vertex IDs on the board with the console list.

#### `drawBoard(ax, state, config)`
Renders the hex grid into the board axes. For each hex: draws a colored `patch` polygon from the 6 corner vertices, draws a circular white dice token with the number and probability pips (6 and 8 shown in red), and labels the resource type. Draws small italic vertex ID numbers on all unoccupied vertices. Draws colored square settlement markers with player numbers on owned vertices.

#### `drawInfoPanel(ax, state, config, playerNames, currentPlayerId, actionStr, rollNum)`
Renders the right-side panel containing: a gold "CATAN" title, the current turn number and dice roll, the last action string, one panel per player (name, type, VP in large text, settlement count, and five colored resource mini-tiles with counts), a win-condition reminder, and a resource color legend.

#### `hexResourceColor(rType)`
Returns the RGB face color for a hex tile by resource type: dark green (wood), red-brown (brick), light green (sheep), yellow (wheat), blue-gray (ore), tan (desert).

#### `playerDisplayColor(playerId)`
Returns a unique display color per player: red (P1), blue (P2), orange (P3), green (P4). Cycles for more than four players.

#### `hexDotCount(diceNum)`
Returns the number of probability pips to draw on a dice token, matching the standard Catan dot convention (5 dots for 6/8, down to 1 dot for 2/12).

#### `createCatanBoard()`
Generates a full-size randomized Catan board with 19 hexes arranged in a radius-2 hex grid. Randomly shuffles the 19 resource tiles (4 wood, 3 brick, 4 sheep, 4 wheat, 3 ore, 1 desert) and 18 dice number tokens. Builds the vertex list by iterating hex corners and deduplicating shared vertices using a coordinate map. Returns a `board` struct with `hexes` and `vertices` arrays.

#### `axialCoordsRadius2()`
Returns the 19 axial coordinate pairs `(q, r)` for all hexes in a radius-2 hexagonal grid, using the cube coordinate distance condition `max(|q|, |r|, |q+r|) ≤ 2`.

#### `axialToCartesian(qr, scale)`
Converts an axial hex coordinate `(q, r)` to a 2D Cartesian position `(x, y)` using a pointy-top hex layout formula. Used to compute hex centers and vertex positions for geometry.

#### `vertexKey(pos)`
Generates a stable string key for a vertex position by rounding `x` and `y` to 6 decimal places and formatting as `"x_y"`. Used as the key in the deduplication map when building the vertex list.

---

### `agent_random.m`

#### `agent_random(state, legalActions, playerId, config)`
Picks a uniformly random action from the legal action list. Does not examine the game state or resource counts. Fast and serves as a baseline for comparison. Useful as a rollout policy in Monte Carlo agents.

---

### `agent_heuristic.m`

#### `agent_heuristic(state, legalActions, playerId, config)`
Greedy agent that scores each legal action and picks the highest-scoring one. Assigns a small negative score to `pass` to prefer building when possible. For `build_settlement`, delegates to `scoreSettlementVertex`.

#### `scoreSettlementVertex(state, playerId, vertexId, config)`
Scores a candidate settlement location using four weighted factors:
- **Expected production** — sum of dice probabilities for adjacent hexes
- **Resource need** — weighted by how short the player is on each resource for the build cost
- **Diversity** — number of new resource types this vertex would provide coverage for
- **Blocking** — number of opponent settlements on adjacent vertices (rewards contested placements)

#### `currentCoverage(state, playerId, config)`
Returns a logical vector indicating which resource types the player currently produces from their existing settlements. Used by `scoreSettlementVertex` to compute the diversity bonus for new placements.

---

### `agent_montecarlo.m`

#### `agent_montecarlo(state, legalActions, playerId, config)`
Flat Monte Carlo agent. For each legal action, runs `config.rolloutCount` random simulations (`config.rolloutHorizon` turns deep) and averages the utility. Picks the action with the highest average utility.

#### `continueTurnWithPolicy(state, playerId, policyName, config)`
Simulates the remainder of a player's turn using a named policy (`'heuristic'` or `'random'`). Keeps applying actions until the player passes or the game ends. Used inside rollouts after the candidate action is applied.

#### `selectPolicyAction(policyName, state, legalActions, playerId, config)`
Selects an action using the named policy. Calls `agent_heuristic` or `agent_random` accordingly. Falls back to `pass` if the returned action is illegal.

#### `rolloutUtility(state, rootPlayer)`
Computes the utility of a rollout terminal state from the perspective of `rootPlayer`. Returns a win bonus (+1.0), loss penalty (−1.0), or 0 for timeout, plus a scaled VP-lead term (×0.10). This is the value function used to rank candidate actions.
