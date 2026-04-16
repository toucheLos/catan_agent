"""
run_tournament.py — Presentation tournament runner.

Round-robin between agents (default: heuristic vs mcts).
Saves timestamped outputs to outputs/:
  YYYYMMDD_HHMMSS_win_rates.csv
  YYYYMMDD_HHMMSS_win_rate_chart.png
  YYYYMMDD_HHMMSS_avg_game_length.csv
  YYYYMMDD_HHMMSS_vp_final.csv

Usage
-----
  python run_tournament.py                            # heuristic vs mcts, 50 games
  python run_tournament.py --agents heuristic mcts --n 20
"""

import argparse
import csv
import os
from datetime import datetime

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

from config import default_config
from agents import resolve_agent
from game import simulate_game

# ── Defaults ──────────────────────────────────────────────────────────────────

DEFAULT_AGENTS = ["heuristic", "mcts"]
DEFAULT_N      = 50
OUTPUT_DIR     = "outputs"
COLORS         = ["#5B9BD5", "#ED7D31", "#70AD47", "#FFC000"]


# ── Core runner ───────────────────────────────────────────────────────────────

def run_presentation_tournament(
    agent_names: list = None,
    N: int = DEFAULT_N,
    config: dict = None,
) -> dict:
    """
    Run a round-robin tournament and save presentation outputs.

    Parameters
    ----------
    agent_names : list of str
        Agent type strings (e.g. ['heuristic', 'mcts']).
    N : int
        Games per ordered matchup.
    config : dict, optional
        Base config; verbose/rng_seed used, viz/pause ignored.

    Returns
    -------
    dict with wins, losses, game_lengths, vp_by_agent
    """
    if agent_names is None:
        agent_names = DEFAULT_AGENTS
    if config is None:
        config = default_config()

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    cfg                = dict(config)
    cfg["verbose"]     = False
    cfg["num_players"] = 2

    # Ordered pairs where a != b
    matchups = [(a, b) for a in agent_names for b in agent_names if a != b]

    # Accumulators
    wins        = {n: 0 for n in agent_names}
    losses      = {n: 0 for n in agent_names}
    game_lengths: list = []
    vp_by_agent = {n: [] for n in agent_names}

    base_seed = cfg.get("rng_seed", 42)
    game_num  = 0

    print(f"\n{'=' * 54}")
    print(f"  TOURNAMENT  ({N} games per ordered matchup)")
    print(f"  Agents: {', '.join(agent_names)}")
    print(f"{'=' * 54}")

    for p1_name, p2_name in matchups:
        p1_wins = 0
        print(f"  {p1_name:<15} (P1)  vs  {p2_name:<15} (P2) ...",
              end="", flush=True)

        for _ in range(N):
            game_num            += 1
            game_cfg             = dict(cfg)
            game_cfg["rng_seed"] = base_seed + game_num

            history = simulate_game(
                [resolve_agent(p1_name), resolve_agent(p2_name)],
                game_cfg,
                player_names=[p1_name, p2_name],
            )
            state = history["final_state"]

            if state.winner_id == 1:
                wins[p1_name]   += 1
                losses[p2_name] += 1
                p1_wins         += 1
            elif state.winner_id == 2:
                wins[p2_name]   += 1
                losses[p1_name] += 1

            game_lengths.append(state.turn_index)
            vp_by_agent[p1_name].append(state.players[1].victory_points)
            vp_by_agent[p2_name].append(state.players[2].victory_points)

        print(f"  {p1_wins}/{N} for P1")

    # ── Console summary ───────────────────────────────────────────────────────

    avg_len = sum(game_lengths) / len(game_lengths)

    print(f"\n{'=' * 54}")
    print("  RESULTS")
    print(f"{'=' * 54}")
    for name in agent_names:
        total   = wins[name] + losses[name]
        rate    = wins[name] / total if total > 0 else 0.0
        avg_vp  = sum(vp_by_agent[name]) / len(vp_by_agent[name])
        print(f"  {name:<15}: {wins[name]}W / {losses[name]}L  "
              f"({rate:.1%} win rate)  avg VP: {avg_vp:.2f}")
    print(f"  Avg game length : {avg_len:.1f} turns")
    print(f"  Total games     : {len(game_lengths)}")

    # ── win_rates.csv ─────────────────────────────────────────────────────────

    wr_path = os.path.join(OUTPUT_DIR, f"{ts}_win_rates.csv")
    with open(wr_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["agent", "wins", "losses", "win_rate"])
        for name in agent_names:
            total = wins[name] + losses[name]
            rate  = wins[name] / total if total > 0 else 0.0
            w.writerow([name, wins[name], losses[name], f"{rate:.4f}"])

    # ── win_rate_chart.png ────────────────────────────────────────────────────

    rates  = []
    for name in agent_names:
        total = wins[name] + losses[name]
        rates.append(wins[name] / total if total > 0 else 0.0)

    colors = COLORS[:len(agent_names)]
    fig, ax = plt.subplots(figsize=(6, 5))
    bars = ax.bar(agent_names, rates, color=colors, width=0.5)

    for bar, rate in zip(bars, rates):
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height() + 0.025,
            f"{rate:.1%}",
            ha="center", va="bottom", fontsize=11, fontweight="bold",
        )

    total_games = len(matchups) * N
    ax.set_ylabel("Win Rate")
    ax.set_title(f"Agent Win Rates  (N={total_games} total games)")
    ax.set_ylim(0, 1.15)
    ax.yaxis.grid(True, linestyle="--", alpha=0.4)
    ax.xaxis.grid(False)
    ax.set_axisbelow(True)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.tick_params(axis="x", bottom=False)
    plt.tight_layout()

    chart_path = os.path.join(OUTPUT_DIR, f"{ts}_win_rate_chart.png")
    plt.savefig(chart_path, dpi=150, bbox_inches="tight")
    plt.close()

    # ── avg_game_length.csv ───────────────────────────────────────────────────

    gl_path = os.path.join(OUTPUT_DIR, f"{ts}_avg_game_length.csv")
    with open(gl_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["metric", "value"])
        w.writerow(["avg_turns",   f"{avg_len:.2f}"])
        w.writerow(["min_turns",   min(game_lengths)])
        w.writerow(["max_turns",   max(game_lengths)])
        w.writerow(["total_games", len(game_lengths)])

    # ── vp_final.csv ──────────────────────────────────────────────────────────

    vp_path = os.path.join(OUTPUT_DIR, f"{ts}_vp_final.csv")
    with open(vp_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["agent", "avg_vp"])
        for name in agent_names:
            avg_vp = sum(vp_by_agent[name]) / len(vp_by_agent[name])
            w.writerow([name, f"{avg_vp:.4f}"])

    print(f"\n  Outputs saved to {OUTPUT_DIR}/{ts}_*.{{csv,png}}")

    return {
        "wins":         wins,
        "losses":       losses,
        "game_lengths": game_lengths,
        "vp_by_agent":  vp_by_agent,
    }


# ── CLI ───────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Presentation tournament runner.")
    parser.add_argument(
        "--agents", nargs="+", default=DEFAULT_AGENTS,
        help="Agent names (default: heuristic mcts)",
    )
    parser.add_argument(
        "--n", type=int, default=DEFAULT_N,
        help="Games per ordered matchup (default: 50)",
    )
    args = parser.parse_args()
    run_presentation_tournament(agent_names=args.agents, N=args.n)
