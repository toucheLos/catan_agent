"""
config.py — Default configuration for the Python Catan engine.

Override any key in the returned dict before passing to simulate_game / run_tournament.
"""

import math


def default_config() -> dict:
    return {
        # ── Game rules ────────────────────────────────────────────────────────
        "num_players": 2,
        "max_turns": 200,
        "win_settlements": 8,

        # ── Resources ─────────────────────────────────────────────────────────
        "resource_names": ["wood", "brick", "sheep", "wheat", "ore"],
        "build_costs": {
            "settlement": {"wood": 1, "brick": 1, "sheep": 1, "wheat": 1},
            "road":       {"wood": 1, "brick": 1},
        },
        "initial_resources": {"wood": 0, "brick": 0, "sheep": 0, "wheat": 0, "ore": 0},

        # ── Board / placement ─────────────────────────────────────────────────
        "initial_free_settlements": 2,
        "enforce_distance_rule": True,

        # Roads extension: if True, settlements (after initial placement) require
        # road connectivity to the player's existing network.
        # Set False to match MATLAB base-game behaviour (no roads).
        "enable_roads": False,

        # ── RNG ───────────────────────────────────────────────────────────────
        "rng_seed": 42,

        # ── Output ────────────────────────────────────────────────────────────
        "verbose": True,

        # ── Monte Carlo / MCTS ────────────────────────────────────────────────
        "rollout_count":   20,   # rollouts per candidate action
        "rollout_horizon": 30,   # max simulated turns per rollout
        "mc": {
            "self_rollout_policy":     "heuristic",  # policy used for own moves in rollouts
            "opponent_rollout_policy": "random",      # policy used for opponent moves
        },

        # ── Heuristic agent weights ───────────────────────────────────────────
        "heuristic": {
            "w_expected_production": 3.0,
            "w_resource_need":       1.5,
            "w_diversity":           1.0,
            "w_blocking":            0.2,
            "w_road_value":          0.5,  # weight for road-expansion heuristic
        },

        # ── MCTS ──────────────────────────────────────────────────────────────
        "mcts": {
            "C": math.sqrt(2),   # UCB1 exploration constant
        },
    }
