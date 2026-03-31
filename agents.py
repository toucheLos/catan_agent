"""
agents.py — Four Catan agents (Python port of MATLAB agent_*.m files).

Agents
------
random_agent       — uniform random over legal actions
heuristic_agent    — greedy weighted score (production, need, diversity, blocking, road value)
monte_carlo_agent  — flat Monte Carlo rollouts; picks highest-average-utility action
mcts_agent         — UCB1 Monte Carlo Tree Search over legal actions

All agents share the same signature:
    fn(state: GameState, legal_actions: List[Action], player_id: int, config: dict) -> Action

Roads extension
---------------
* heuristic_agent scores build_road by how many new settlement spots it unlocks.
* MC / MCTS rollout policies include road-building when choosing actions.
* _continue_turn_with_policy loops until the player passes (exhausts all
  affordable actions in a single simulated turn).
"""

import math
import random as _random
from typing import List

from game import (
    GameState, Action, RESOURCES,
    enumerate_legal_actions, apply_action, check_terminal,
    distribute_resources, roll_dice, is_legal_action,
)
from board import dice_probability


# ═══════════════════════════════════════════════════════════════════════════════
# Random agent
# ═══════════════════════════════════════════════════════════════════════════════

def random_agent(state: GameState, legal_actions: List[Action],
                 player_id: int, config: dict) -> Action:
    """Uniform random selection from legal actions."""
    return _random.choice(legal_actions)


# ═══════════════════════════════════════════════════════════════════════════════
# Heuristic agent
# ═══════════════════════════════════════════════════════════════════════════════

def heuristic_agent(state: GameState, legal_actions: List[Action],
                    player_id: int, config: dict) -> Action:
    """
    Greedy action selection using a weighted sum of features.

    Settlement score = w_prod  * expected_production
                     + w_need  * resource_need_score
                     + w_div   * new_resource_types_covered
                     + w_blk   * adjacent_opponent_settlements

    Road score       = w_road  * new_settlement_spots_unlocked

    Weights are read from config['heuristic'] (falls back to hard-coded defaults).
    """
    hw      = config.get("heuristic", {})
    w_prod  = hw.get("w_expected_production", 3.0)
    w_need  = hw.get("w_resource_need",       1.5)
    w_div   = hw.get("w_diversity",           1.0)
    w_blk   = hw.get("w_blocking",            0.2)
    w_road  = hw.get("w_road_value",          0.5)

    best_score  = float("-inf")
    best_action = Action("pass")

    for action in legal_actions:
        if action.action_type == "pass":
            score = -0.05
        elif action.action_type == "build_settlement":
            score = _score_settlement(state, player_id, action.vertex_id, config,
                                      w_prod, w_need, w_div, w_blk)
        elif action.action_type == "build_road":
            score = _score_road(state, player_id, action.edge_id, config, w_road)
        else:
            score = float("-inf")

        if score > best_score:
            best_score  = score
            best_action = action

    return best_action


def _current_coverage(state: GameState, player_id: int) -> set:
    """Resource types already produced by player's existing settlements."""
    covered: set = set()
    for vid, owner in enumerate(state.vertex_owners):
        if owner != player_id:
            continue
        for hid in state.board.vertices[vid].adj_hex_ids:
            rtype = state.board.hexes[hid].resource_type
            if rtype != "desert":
                covered.add(rtype)
    return covered


def _score_settlement(state: GameState, player_id: int, vertex_id: int,
                      config: dict,
                      w_prod: float, w_need: float, w_div: float, w_blk: float
                      ) -> float:
    """Score a candidate settlement vertex (mirrors MATLAB scoreSettlementVertex)."""
    board    = state.board
    vertex   = board.vertices[vertex_id]
    player   = state.players[player_id]
    s_cost   = config["build_costs"]["settlement"]

    exp_prod        = 0.0
    res_need        = 0.0
    produced_types: set = set()

    for hid in vertex.adj_hex_ids:
        h = board.hexes[hid]
        if h.resource_type == "desert":
            continue
        p = dice_probability(h.dice_number)
        exp_prod += p
        produced_types.add(h.resource_type)

        demand  = s_cost.get(h.resource_type, 0)
        missing = max(demand - player.resources.get(h.resource_type, 0), 0)
        res_need += p * missing

    existing_covered  = _current_coverage(state, player_id)
    new_coverage      = len(produced_types - existing_covered)

    blocking = sum(
        1 for nb in vertex.adj_vertex_ids
        if state.vertex_owners[nb] not in (0, player_id)
    )

    return (w_prod * exp_prod
            + w_need * res_need
            + w_div  * new_coverage
            + w_blk  * blocking)


def _score_road(state: GameState, player_id: int, edge_id: int,
                config: dict, w_road: float) -> float:
    """
    Score a road by how many new valid settlement vertices it exposes.

    A vertex is 'newly exposed' if it is:
    * unoccupied
    * satisfies the distance rule
    * not already reachable via the player's existing road network
    * incident to this edge endpoint (i.e. the road reaches it)
    """
    board    = state.board
    edge     = board.edges[edge_id]
    enforce  = config.get("enforce_distance_rule", True)

    new_spots = 0
    for v in (edge.v1, edge.v2):
        if state.vertex_owners[v] != 0:
            continue
        if enforce and any(state.vertex_owners[nb] != 0
                           for nb in board.vertices[v].adj_vertex_ids):
            continue
        # Count if this vertex isn't already in the player's reachable set
        already_reachable = any(
            state.edge_owners[e2] == player_id
            for e2 in board.vertex_edges[v]
        )
        if not already_reachable:
            new_spots += 1

    return w_road * new_spots


# ═══════════════════════════════════════════════════════════════════════════════
# Shared rollout utilities (used by Monte Carlo and MCTS)
# ═══════════════════════════════════════════════════════════════════════════════

def _select_policy_action(policy: str, state: GameState, legal_actions: List[Action],
                          player_id: int, config: dict) -> Action:
    """Dispatch to named policy; fall back to pass if action is somehow illegal."""
    if policy == "heuristic":
        action = heuristic_agent(state, legal_actions, player_id, config)
    else:
        action = random_agent(state, legal_actions, player_id, config)

    return action if is_legal_action(action, legal_actions) else Action("pass")


def _continue_turn_with_policy(state: GameState, player_id: int,
                               policy: str, config: dict) -> GameState:
    """
    Let *player_id* keep taking actions (under *policy*) until they pass or the
    game ends.  An action cap prevents infinite loops.

    Mirrors MATLAB continueTurnWithPolicy / mctsApplyPolicy.
    """
    cap = len(state.board.vertices) + len(state.board.edges) + 1
    for _ in range(cap):
        legal  = enumerate_legal_actions(state, player_id, config)
        action = _select_policy_action(policy, state, legal, player_id, config)
        apply_action(state, player_id, action, config)

        done, winner       = check_terminal(state, config)
        state.is_terminal  = done
        state.winner_id    = winner

        if done or action.action_type == "pass":
            break
    return state


def _run_rollout_horizon(state: GameState, root_player: int, config: dict) -> None:
    """
    Simulate *rollout_horizon* full turns starting from *state* (mutates in-place).
    Each player acts under their designated rollout policy.
    """
    horizon     = config.get("rollout_horizon", 30)
    num_players = config["num_players"]
    self_policy = config.get("mc", {}).get("self_rollout_policy",     "heuristic")
    opp_policy  = config.get("mc", {}).get("opponent_rollout_policy", "random")

    for _ in range(horizon):
        if state.is_terminal:
            break

        cp             = state.current_player
        state.last_roll = roll_dice()
        distribute_resources(state, state.last_roll, config)

        policy = self_policy if cp == root_player else opp_policy
        _continue_turn_with_policy(state, cp, policy, config)

        if not state.is_terminal:
            state.current_player = (cp % num_players) + 1
            state.turn_index    += 1
            done, winner         = check_terminal(state, config)
            state.is_terminal    = done
            state.winner_id      = winner


def _rollout_utility(state: GameState, root_player: int) -> float:
    """
    Scalar utility for *root_player* at end of rollout.

    utility = win_bonus  (+1 win, −1 loss, 0 otherwise)
            + 0.10 * vp_lead   (VP above best opponent)

    Mirrors MATLAB rolloutUtility / mctsUtility.
    """
    my_vp    = state.players[root_player].victory_points
    opp_vps  = [p.victory_points for pid, p in state.players.items()
                if pid != root_player]
    max_opp  = max(opp_vps) if opp_vps else my_vp
    vp_lead  = my_vp - max_opp

    win_bonus = 0.0
    if state.is_terminal:
        if state.winner_id == root_player:
            win_bonus = 1.0
        elif state.winner_id != 0:
            win_bonus = -1.0

    return win_bonus + 0.10 * vp_lead


def _single_rollout(state: GameState, candidate: Action, player_id: int,
                    config: dict) -> float:
    """
    Apply *candidate*, finish the current player's turn under self-policy,
    then simulate *rollout_horizon* more turns.  Returns scalar utility.

    Shared by both Monte Carlo and MCTS agents.
    """
    rs = state.copy()
    apply_action(rs, player_id, candidate, config)

    done, winner     = check_terminal(rs, config)
    rs.is_terminal   = done
    rs.winner_id     = winner

    self_policy = config.get("mc", {}).get("self_rollout_policy", "heuristic")

    # Finish this player's turn (may build road then settle, etc.)
    if not rs.is_terminal and candidate.action_type != "pass":
        _continue_turn_with_policy(rs, player_id, self_policy, config)

    # Advance to next player
    if not rs.is_terminal:
        rs.current_player = (player_id % config["num_players"]) + 1
        rs.turn_index    += 1

    _run_rollout_horizon(rs, player_id, config)
    return _rollout_utility(rs, player_id)


# ═══════════════════════════════════════════════════════════════════════════════
# Monte Carlo agent  (flat MC, mirrors MATLAB agent_montecarlo.m)
# ═══════════════════════════════════════════════════════════════════════════════

def monte_carlo_agent(state: GameState, legal_actions: List[Action],
                      player_id: int, config: dict) -> Action:
    """
    For each legal action run *rollout_count* forward rollouts and pick the
    action with the highest average utility.

    Self plays heuristic in rollouts; opponents play random (configurable via
    config['mc']['self_rollout_policy'] / 'opponent_rollout_policy').
    """
    rollout_count = config.get("rollout_count", 20)

    best_value  = float("-inf")
    best_action = Action("pass")

    for candidate in legal_actions:
        total = sum(
            _single_rollout(state, candidate, player_id, config)
            for _ in range(rollout_count)
        )
        value = total / rollout_count
        if value > best_value:
            best_value  = value
            best_action = candidate

    return best_action


# ═══════════════════════════════════════════════════════════════════════════════
# MCTS agent  (one-level UCB1, mirrors MATLAB agent_mcts.m)
# ═══════════════════════════════════════════════════════════════════════════════

def mcts_agent(state: GameState, legal_actions: List[Action],
               player_id: int, config: dict) -> Action:
    """
    UCB1-based allocation of a fixed rollout budget across legal actions.

    Budget = rollout_count × num_actions  (same total as flat MC).
    Each action is seeded with one rollout, then UCB1 allocates the remainder.
    Returns the action with the highest average utility at budget exhaustion.

    Key config fields:
        config['rollout_count']   — rollouts per action (budget = count × N)
        config['rollout_horizon'] — max simulated turns per rollout
        config['mcts']['C']       — UCB1 exploration constant (default √2)
    """
    num_actions = len(legal_actions)
    if num_actions == 1:
        return legal_actions[0]

    C            = config.get("mcts", {}).get("C", math.sqrt(2))
    total_budget = config.get("rollout_count", 20) * num_actions

    visit_counts = [0]   * num_actions
    total_values = [0.0] * num_actions

    # ── Seed phase: one rollout per action so UCB1 never divides by zero ──────
    for i, candidate in enumerate(legal_actions):
        total_values[i]  = _single_rollout(state, candidate, player_id, config)
        visit_counts[i]  = 1
    total_visits     = num_actions
    remaining_budget = total_budget - num_actions

    # ── UCB1 selection loop ───────────────────────────────────────────────────
    for _ in range(remaining_budget):
        log_n = math.log(total_visits)
        ucb   = [
            (total_values[i] / visit_counts[i]) + C * math.sqrt(log_n / visit_counts[i])
            for i in range(num_actions)
        ]
        idx = ucb.index(max(ucb))

        v                  = _single_rollout(state, legal_actions[idx], player_id, config)
        visit_counts[idx] += 1
        total_values[idx] += v
        total_visits      += 1

    # ── Best action by average value ──────────────────────────────────────────
    avgs    = [total_values[i] / visit_counts[i] for i in range(num_actions)]
    return legal_actions[avgs.index(max(avgs))]


# ═══════════════════════════════════════════════════════════════════════════════
# Agent registry
# ═══════════════════════════════════════════════════════════════════════════════

AGENT_REGISTRY = {
    "random":       random_agent,
    "heuristic":    heuristic_agent,
    "monte_carlo":  monte_carlo_agent,
    "mcts":         mcts_agent,
}


def resolve_agent(name: str):
    """Return agent function by name string (case-insensitive)."""
    fn = AGENT_REGISTRY.get(name.lower())
    if fn is None:
        raise ValueError(
            f"Unknown agent '{name}'. Choose from: {list(AGENT_REGISTRY)}"
        )
    return fn
