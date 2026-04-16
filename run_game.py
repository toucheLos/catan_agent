"""
run_game.py — Single-game runner with per-turn logging and VP chart.

Runs one full game (heuristic vs mcts, no display).
Saves timestamped outputs to outputs/:
  YYYYMMDD_HHMMSS_game_log.csv
  YYYYMMDD_HHMMSS_vp_over_time.png

Usage
-----
  python run_game.py
"""

import csv
import os
from collections import defaultdict
from datetime import datetime

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

from config import default_config
from agents import resolve_agent
from game import simulate_game

# ── Defaults ──────────────────────────────────────────────────────────────────

DEFAULT_AGENTS = ["heuristic", "mcts"]
OUTPUT_DIR     = "outputs"
COLORS         = ["#5B9BD5", "#ED7D31"]


# ── Runner ────────────────────────────────────────────────────────────────────

def run_single_game(
    agent_names: list = None,
    config: dict = None,
) -> dict:
    """
    Run one game and save a per-turn CSV log and VP-over-time chart.

    Parameters
    ----------
    agent_names : list of str
        Exactly 2 agent names (default: ['heuristic', 'mcts']).
    config : dict, optional
        Base config dict; verbose is forced False.

    Returns
    -------
    history dict from simulate_game
    """
    if agent_names is None:
        agent_names = DEFAULT_AGENTS
    if config is None:
        config = default_config()

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    cfg                = dict(config)
    cfg["verbose"]     = False
    cfg["num_players"] = len(agent_names)

    agent_fns = [resolve_agent(n) for n in agent_names]
    history   = simulate_game(agent_fns, cfg, player_names=agent_names)
    state     = history["final_state"]

    # ── Console output ────────────────────────────────────────────────────────

    winner_pid  = state.winner_id
    winner_name = (agent_names[winner_pid - 1]
                   if 1 <= winner_pid <= len(agent_names)
                   else "None")

    print(f"\nGame over!")
    print(f"Winner     : {winner_name} (Player {winner_pid})")
    print(f"Total turns: {state.turn_index}")
    for pid, name in enumerate(agent_names, start=1):
        print(f"  P{pid} ({name}): {state.players[pid].victory_points} VP")

    # ── game_log.csv ──────────────────────────────────────────────────────────

    log_path = os.path.join(OUTPUT_DIR, f"{ts}_game_log.csv")
    with open(log_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["turn", "player_id", "agent_type", "action_type", "vp_after"])
        for entry in history["actions"]:
            w.writerow([
                entry["turn"],
                entry["player"],
                agent_names[entry["player"] - 1],
                entry["type"],
                entry["vp"],
            ])

    # ── vp_over_time.png ──────────────────────────────────────────────────────
    # Build one (turns, vps) series per player from the action log.
    # Only turns where the player acted are recorded; ax.step() fills the gaps.

    vp_series: dict = defaultdict(list)  # pid → [(turn, vp), ...]
    for entry in history["actions"]:
        vp_series[entry["player"]].append((entry["turn"], entry["vp"]))

    fig, ax = plt.subplots(figsize=(10, 5))

    for pid, name in enumerate(agent_names, start=1):
        pts = vp_series.get(pid, [])
        if not pts:
            continue
        turns = [t for t, _ in pts]
        vps   = [v for _, v in pts]
        ax.step(turns, vps, where="post",
                label=name, color=COLORS[pid - 1], linewidth=2)

    ax.set_xlabel("Turn")
    ax.set_ylabel("Victory Points")
    ax.set_title("VP Progression")
    ax.legend()
    ax.yaxis.grid(True, linestyle="--", alpha=0.4)
    ax.xaxis.grid(False)
    ax.set_axisbelow(True)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    plt.tight_layout()

    chart_path = os.path.join(OUTPUT_DIR, f"{ts}_vp_over_time.png")
    plt.savefig(chart_path, dpi=150, bbox_inches="tight")
    plt.close()

    print(f"\n  Outputs saved to {OUTPUT_DIR}/{ts}_*.{{csv,png}}")
    return history


# ── CLI ───────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    run_single_game()
