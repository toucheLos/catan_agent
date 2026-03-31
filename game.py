"""
game.py — Catan game engine (Python port of MATLAB catan_core.m).

Public API
----------
init_game(config)                                     → GameState
simulate_game(agent_fns, config, player_names=None)   → history dict
enumerate_legal_actions(state, player_id, config, free=False)  → List[Action]
apply_action(state, player_id, action, config, free=False)     → GameState
distribute_resources(state, roll, config)             → GameState (in-place)
check_terminal(state, config)                         → (done: bool, winner_id: int)
roll_dice()                                           → int
dice_probability(n)                                   → float

Roads extension
---------------
When config['enable_roads'] is True (default), settlements placed after the
initial free rounds require road connectivity to the player's existing network.
Roads are built via Action('build_road', edge_id=...) at cost 1 wood + 1 brick.
"""

import random as _random
from typing import Callable, Dict, List, Optional, Tuple

from board import Board, create_board, dice_probability

RESOURCES = ["wood", "brick", "sheep", "wheat", "ore"]


# ── Action ────────────────────────────────────────────────────────────────────

class Action:
    """
    A player action.  action_type is one of:
      'pass'              — do nothing this turn
      'build_settlement'  — place a settlement at vertex_id
      'build_road'        — place a road at edge_id
    """
    __slots__ = ("action_type", "vertex_id", "edge_id")

    def __init__(self, action_type: str, vertex_id: int = 0, edge_id: int = 0):
        self.action_type = action_type
        self.vertex_id   = vertex_id
        self.edge_id     = edge_id

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, Action):
            return NotImplemented
        return (self.action_type == other.action_type and
                self.vertex_id   == other.vertex_id   and
                self.edge_id     == other.edge_id)

    def __repr__(self) -> str:
        if self.action_type == "build_settlement":
            return f"Action(build_settlement, v={self.vertex_id})"
        if self.action_type == "build_road":
            return f"Action(build_road, e={self.edge_id})"
        return f"Action({self.action_type})"


# ── PlayerState ───────────────────────────────────────────────────────────────

class PlayerState:
    __slots__ = ("pid", "resources", "settlement_count", "victory_points")

    def __init__(self, pid: int, initial_resources: Dict[str, int]):
        self.pid              = pid
        self.resources        = dict(initial_resources)
        self.settlement_count = 0
        self.victory_points   = 0

    def copy(self) -> "PlayerState":
        p = PlayerState.__new__(PlayerState)
        p.pid              = self.pid
        p.resources        = self.resources.copy()
        p.settlement_count = self.settlement_count
        p.victory_points   = self.victory_points
        return p

    def can_afford(self, cost: Dict[str, int]) -> bool:
        return all(self.resources.get(r, 0) >= amt for r, amt in cost.items())

    def pay(self, cost: Dict[str, int]) -> None:
        for r, amt in cost.items():
            self.resources[r] -= amt


# ── GameState ─────────────────────────────────────────────────────────────────

class GameState:
    """
    Mutable game state.  The board topology (Board object) is shared across
    copies; only ownership arrays and player resources are copied.
    """
    __slots__ = (
        "board", "players", "vertex_owners", "edge_owners",
        "turn_index", "current_player", "last_roll",
        "is_terminal", "winner_id",
    )

    def __init__(self, board: Board, players: Dict[int, PlayerState],
                 vertex_owners: List[int], edge_owners: List[int]):
        self.board          = board           # shared, never mutated
        self.players        = players         # 1-indexed
        self.vertex_owners  = vertex_owners   # list[int], 0 = unowned
        self.edge_owners    = edge_owners     # list[int], 0 = unowned
        self.turn_index     = 1
        self.current_player = 1
        self.last_roll      = 0
        self.is_terminal    = False
        self.winner_id      = 0

    def copy(self) -> "GameState":
        """Shallow-copy mutable fields; share the immutable board."""
        s = GameState.__new__(GameState)
        s.board         = self.board
        s.vertex_owners = self.vertex_owners.copy()
        s.edge_owners   = self.edge_owners.copy()
        s.players       = {pid: p.copy() for pid, p in self.players.items()}
        s.turn_index    = self.turn_index
        s.current_player = self.current_player
        s.last_roll     = self.last_roll
        s.is_terminal   = self.is_terminal
        s.winner_id     = self.winner_id
        return s


# ── Core helpers ──────────────────────────────────────────────────────────────

def roll_dice() -> int:
    """Roll two d6 and return their sum (2–12)."""
    return _random.randint(1, 6) + _random.randint(1, 6)


def distribute_resources(state: GameState, roll: int, config: dict) -> GameState:
    """Award resources to every settlement on a hex matching *roll* (in-place)."""
    for vid, owner in enumerate(state.vertex_owners):
        if owner == 0:
            continue
        for hid in state.board.vertices[vid].adj_hex_ids:
            h = state.board.hexes[hid]
            if h.dice_number == roll and h.resource_type != "desert":
                state.players[owner].resources[h.resource_type] += 1
    return state


def is_legal_action(action: Action, legal_actions: List[Action]) -> bool:
    return any(action == a for a in legal_actions)


def check_terminal(state: GameState, config: dict) -> Tuple[bool, int]:
    """Return (done, winner_id).  winner_id=0 on draw / turn-cap with tie."""
    win_thresh = config["win_settlements"]
    for pid, player in state.players.items():
        if player.settlement_count >= win_thresh:
            return True, pid
    if state.turn_index > config["max_turns"]:
        best = max(state.players, key=lambda p: state.players[p].victory_points)
        return True, best
    return False, 0


# ── Road connectivity ─────────────────────────────────────────────────────────

def is_road_connected(state: GameState, vertex_id: int, player_id: int) -> bool:
    """
    True if *vertex_id* is reachable from any of *player_id*'s settlements
    by traversing only edges owned by *player_id*.

    Used to enforce that settlements (after initial placement) must lie at
    the end of the player's road network.
    """
    board = state.board
    visited: set = set()
    stack: List[int] = []

    # Seed: all vertices owned by this player
    for vid, owner in enumerate(state.vertex_owners):
        if owner == player_id:
            stack.append(vid)
            visited.add(vid)

    while stack:
        cur = stack.pop()
        if cur == vertex_id:
            return True
        for eid in board.vertex_edges[cur]:
            if state.edge_owners[eid] == player_id:
                edge = board.edges[eid]
                nxt  = edge.v2 if edge.v1 == cur else edge.v1
                if nxt not in visited:
                    visited.add(nxt)
                    stack.append(nxt)

    return vertex_id in visited


# ── Legal action enumeration ──────────────────────────────────────────────────

def enumerate_legal_actions(state: GameState, player_id: int, config: dict,
                            free: bool = False) -> List[Action]:
    """
    Return all legal actions for *player_id*.

    Parameters
    ----------
    free : bool
        If True, ignore resource costs and road-connectivity requirements
        (used during initial placement).
    """
    board   = state.board
    player  = state.players[player_id]
    actions = [Action("pass")]

    settlement_cost = config["build_costs"]["settlement"]
    road_cost       = config["build_costs"]["road"]
    enforce_dist    = config.get("enforce_distance_rule", True)
    enable_roads    = config.get("enable_roads", True)

    # ── Settlement placement ──────────────────────────────────────────────────
    if free or player.can_afford(settlement_cost):
        for vid in range(len(board.vertices)):
            if state.vertex_owners[vid] != 0:
                continue
            if enforce_dist:
                if any(state.vertex_owners[nb] != 0
                       for nb in board.vertices[vid].adj_vertex_ids):
                    continue
            # Road connectivity check (skipped during free initial placement)
            if not free and enable_roads:
                if not is_road_connected(state, vid, player_id):
                    continue
            actions.append(Action("build_settlement", vertex_id=vid))

    # ── Road placement (only during normal turns) ─────────────────────────────
    if not free and enable_roads and player.can_afford(road_cost):
        for eid in range(len(board.edges)):
            if state.edge_owners[eid] != 0:
                continue
            edge = board.edges[eid]
            # Edge is buildable if either endpoint connects to player's network
            connected = False
            for v in (edge.v1, edge.v2):
                if state.vertex_owners[v] == player_id:
                    connected = True
                    break
                for e2 in board.vertex_edges[v]:
                    if state.edge_owners[e2] == player_id:
                        connected = True
                        break
                if connected:
                    break
            if connected:
                actions.append(Action("build_road", edge_id=eid))

    return actions


# ── Apply action ──────────────────────────────────────────────────────────────

def apply_action(state: GameState, player_id: int, action: Action,
                 config: dict, free: bool = False) -> GameState:
    """
    Apply *action* to *state* (mutates in-place) and return *state*.

    Silently ignores illegal actions (no-op).
    """
    board   = state.board
    player  = state.players[player_id]
    enforce = config.get("enforce_distance_rule", True)

    if action.action_type == "pass":
        return state

    if action.action_type == "build_settlement":
        vid = action.vertex_id
        if vid < 0 or vid >= len(board.vertices):
            return state
        if state.vertex_owners[vid] != 0:
            return state
        if enforce:
            if any(state.vertex_owners[nb] != 0
                   for nb in board.vertices[vid].adj_vertex_ids):
                return state
        if not free:
            cost = config["build_costs"]["settlement"]
            if not player.can_afford(cost):
                return state
            player.pay(cost)
        state.vertex_owners[vid]    = player_id
        player.settlement_count    += 1
        player.victory_points       = player.settlement_count

    elif action.action_type == "build_road":
        eid = action.edge_id
        if eid < 0 or eid >= len(board.edges):
            return state
        if state.edge_owners[eid] != 0:
            return state
        cost = config["build_costs"]["road"]
        if not player.can_afford(cost):
            return state
        player.pay(cost)
        state.edge_owners[eid] = player_id

    return state


# ── Game initialisation ───────────────────────────────────────────────────────

def init_game(config: dict) -> GameState:
    """Seed RNG, build board, return the starting state."""
    _random.seed(config["rng_seed"])
    board       = create_board()
    num_players = config["num_players"]
    init_res    = dict(config["initial_resources"])
    players     = {i + 1: PlayerState(i + 1, init_res) for i in range(num_players)}
    return GameState(
        board         = board,
        players       = players,
        vertex_owners = [0] * len(board.vertices),
        edge_owners   = [0] * len(board.edges),
    )


# ── Initial placement ─────────────────────────────────────────────────────────

def _greedy_placement(state: GameState, legal: List[Action]) -> Action:
    """
    Fallback placement for rollout-based agents: pick the settlement vertex with
    the highest expected dice production across adjacent hexes.
    Used when MC/MCTS agents return pass during free initial placement.
    """
    best_score  = float("-inf")
    best_action = next((a for a in legal if a.action_type == "build_settlement"), legal[0])
    for action in legal:
        if action.action_type != "build_settlement":
            continue
        score = sum(
            dice_probability(state.board.hexes[hid].dice_number)
            for hid in state.board.vertices[action.vertex_id].adj_hex_ids
            if state.board.hexes[hid].resource_type != "desert"
        )
        if score > best_score:
            best_score  = score
            best_action = action
    return best_action


def _initial_placement(state: GameState, agent_fns: List[Callable],
                       config: dict, player_names: List[str]) -> GameState:
    """Each player places K free settlements (no resource cost, no road req.)."""
    K           = config.get("initial_free_settlements", 2)
    num_players = config["num_players"]
    verbose     = config.get("verbose", True)

    if verbose:
        print(f"=== Initial Placement ({K} free settlement(s) each) ===")

    for round_ in range(K):
        for p in range(1, num_players + 1):
            legal  = enumerate_legal_actions(state, p, config, free=True)
            if verbose:
                print(f"  [Round {round_ + 1}] Player {p} ({player_names[p - 1]}) placing...")
            action = agent_fns[p - 1](state, legal, p, config)
            if not is_legal_action(action, legal) or action.action_type == "pass":
                # Rollout-based agents (MC/MCTS) may return pass during free
                # placement because they can't afford settlements in their rollouts.
                # Fall back to greedy expected-production placement.
                action = _greedy_placement(state, legal)
            apply_action(state, p, action, config, free=True)
            if verbose and action.action_type == "build_settlement":
                print(f"    P{p} placed settlement at vertex {action.vertex_id}")

    if verbose:
        print("=== Placement complete. Starting game. ===\n")
    return state


# ── Main game loop ────────────────────────────────────────────────────────────

def simulate_game(agent_fns: List[Callable], config: dict,
                  player_names: Optional[List[str]] = None) -> dict:
    """
    Run one complete game.

    Parameters
    ----------
    agent_fns : list of callables
        Each callable has signature  fn(state, legal_actions, player_id, config) → Action.
    config : dict
        Game configuration (from config.default_config()).
    player_names : list of str, optional
        Display names; defaults to ['P1', 'P2', ...].

    Returns
    -------
    history : dict with keys
        'actions'     — list of per-turn dicts
        'logs'        — list of log strings
        'final_state' — GameState at game end
    """
    num_players  = len(agent_fns)
    cfg          = dict(config)
    cfg["num_players"] = num_players

    if player_names is None:
        player_names = [f"P{i + 1}" for i in range(num_players)]

    verbose = cfg.get("verbose", True)

    # ── Initialise ────────────────────────────────────────────────────────────
    _random.seed(cfg["rng_seed"])
    board    = create_board()
    init_res = dict(cfg["initial_resources"])
    players  = {i + 1: PlayerState(i + 1, init_res) for i in range(num_players)}
    state    = GameState(
        board         = board,
        players       = players,
        vertex_owners = [0] * len(board.vertices),
        edge_owners   = [0] * len(board.edges),
    )

    # ── Initial free placement ────────────────────────────────────────────────
    state = _initial_placement(state, agent_fns, cfg, player_names)

    history: dict = {"actions": [], "logs": [], "final_state": None}

    # ── Main turn loop ────────────────────────────────────────────────────────
    while not state.is_terminal:
        pid           = state.current_player
        state.last_roll = roll_dice()
        distribute_resources(state, state.last_roll, cfg)

        if verbose:
            res_str = "  ".join(
                f"{r}:{state.players[pid].resources[r]}" for r in RESOURCES
            )
            print("----------------------------------------")
            print(f"Turn {state.turn_index} | Player {pid} "
                  f"({player_names[pid - 1]}) | Roll: {state.last_roll}")
            print(f"  Resources: {res_str} | VP: {state.players[pid].victory_points}")

        legal  = enumerate_legal_actions(state, pid, cfg)
        action = agent_fns[pid - 1](state, legal, pid, cfg)

        if not is_legal_action(action, legal):
            action = Action("pass")

        apply_action(state, pid, action, cfg)

        # Build log line
        log = f"P{pid} ({player_names[pid - 1]}) -> {action.action_type}"
        if action.action_type == "build_settlement":
            log += f" @v{action.vertex_id}"
        elif action.action_type == "build_road":
            log += f" @e{action.edge_id}"
        log += f" | VP={state.players[pid].victory_points}"

        if verbose:
            print(log)

        history["logs"].append(log)
        history["actions"].append({
            "turn":      state.turn_index,
            "player":    pid,
            "roll":      state.last_roll,
            "type":      action.action_type,
            "vertex_id": action.vertex_id,
            "edge_id":   action.edge_id,
            "vp":        state.players[pid].victory_points,
        })

        done, winner = check_terminal(state, cfg)
        state.is_terminal = done
        state.winner_id   = winner
        if state.is_terminal:
            break

        state.current_player = (pid % num_players) + 1
        state.turn_index    += 1
        done, winner         = check_terminal(state, cfg)
        state.is_terminal    = done
        state.winner_id      = winner

    history["final_state"] = state
    return history
