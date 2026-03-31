"""
tournament.py — Tournament runner and heuristic weight tuner.

Public API
----------
run_tournament(agent_names, N=50, config=None)
    Round-robin tournament: N games per ordered matchup.
    Outputs win-rate matrix with 95% CIs to console + tournament_results.csv.

tune_heuristic_weights(weight_values=None, N_games=20, config=None, verbose=True)
    Grid search over (w1, w2, w3, w4) maximising heuristic win rate vs random.
    Outputs top configs to console + weight_tuning_results.csv.

95 % confidence intervals use the normal approximation:
    p_hat ± 1.96 × sqrt(p_hat × (1 − p_hat) / n)
"""

import csv
import math
import random as _random
from itertools import product as _product
from typing import Dict, List, Optional, Tuple

from config import default_config
from game import simulate_game
from agents import resolve_agent, heuristic_agent


# ── Confidence interval helper ────────────────────────────────────────────────

def _ci95(p_hat: float, n: int) -> Tuple[float, float]:
    """95 % normal-approximation CI for a proportion."""
    if n == 0:
        return (0.0, 1.0)
    margin = 1.96 * math.sqrt(p_hat * (1.0 - p_hat) / n)
    return (max(0.0, p_hat - margin), min(1.0, p_hat + margin))


# ═══════════════════════════════════════════════════════════════════════════════
# Tournament
# ═══════════════════════════════════════════════════════════════════════════════

def run_tournament(agent_names: List[str], N: int = 50,
                   config: Optional[dict] = None) -> dict:
    """
    Round-robin 2-player tournament.

    Parameters
    ----------
    agent_names : list of str
        Agent type strings: 'random', 'heuristic', 'monte_carlo', 'mcts'.
    N : int
        Games per *ordered* matchup.  Each unordered pair plays 2N games total
        (N as P1, N as P2), matching the MATLAB tournament design.
    config : dict, optional
        Base config; verbose / rng_seed used.  viz and pause are ignored.

    Returns
    -------
    results : dict
        names, win_rate_matrix, ci_matrix, overall_win_rates,
        wins_as_p1, wins_as_p2, games_per_agent, N
    """
    if config is None:
        config = default_config()

    cfg              = dict(config)
    cfg["verbose"]   = False
    cfg["num_players"] = 2

    num_agents = len(agent_names)
    agent_fns  = [resolve_agent(name) for name in agent_names]

    # wins[i][j] = number of games where agent i (playing as P1) beat agent j (P2)
    wins: List[List[int]] = [[0] * num_agents for _ in range(num_agents)]

    print(f"\n{'=' * 56}")
    print(f"  TOURNAMENT  ({N} games per ordered matchup)")
    print(f"{'=' * 56}")

    base_seed = cfg.get("rng_seed", 42)
    game_num  = 0

    for i in range(num_agents):
        for j in range(num_agents):
            if i == j:
                continue
            print(f"  {agent_names[i]:<15} (P1)  vs  {agent_names[j]:<15} (P2) ...",
                  end="", flush=True)

            for g in range(N):
                game_num         += 1
                game_cfg          = dict(cfg)
                game_cfg["rng_seed"] = base_seed + game_num

                history = simulate_game([agent_fns[i], agent_fns[j]], game_cfg)
                if history["final_state"].winner_id == 1:
                    wins[i][j] += 1

            print(f"  {wins[i][j]}/{N} for P1")

    # ── Statistics ────────────────────────────────────────────────────────────

    # Win-rate matrix (None on diagonal)
    win_rate_matrix: List[List] = [
        [wins[i][j] / N if i != j else None for j in range(num_agents)]
        for i in range(num_agents)
    ]

    # 95 % CI matrix
    ci_matrix: List[List] = [
        [_ci95(win_rate_matrix[i][j], N) if i != j else (None, None)
         for j in range(num_agents)]
        for i in range(num_agents)
    ]

    # Overall win rates (P1 + P2 combined)
    wins_as_p1 = [
        sum(wins[i][j] for j in range(num_agents) if j != i)
        for i in range(num_agents)
    ]
    wins_as_p2 = [
        sum(N - wins[j][i] for j in range(num_agents) if j != i)
        for i in range(num_agents)
    ]
    games_per_agent  = (num_agents - 1) * 2 * N
    overall_win_rate = [
        (wins_as_p1[i] + wins_as_p2[i]) / games_per_agent
        for i in range(num_agents)
    ]

    # ── Console output ────────────────────────────────────────────────────────
    _print_win_rate_table(agent_names, win_rate_matrix, ci_matrix)

    print(f"\n--- Overall Win Rate (P1 + P2 combined, 95 % CI) ---")
    for i, name in enumerate(agent_names):
        lo, hi = _ci95(overall_win_rate[i], games_per_agent)
        total  = wins_as_p1[i] + wins_as_p2[i]
        print(f"  {name:<15}: {overall_win_rate[i]:.3f}  "
              f"95 % CI [{lo:.3f}, {hi:.3f}]  "
              f"({total}/{games_per_agent})")
    print(f"{'=' * 56}\n")

    # ── CSV output ────────────────────────────────────────────────────────────
    _write_tournament_csv(
        agent_names, win_rate_matrix, ci_matrix,
        overall_win_rate, wins_as_p1, wins_as_p2, games_per_agent, N,
    )

    return {
        "names":            agent_names,
        "win_rate_matrix":  win_rate_matrix,
        "ci_matrix":        ci_matrix,
        "overall_win_rates": overall_win_rate,
        "wins_as_p1":       wins_as_p1,
        "wins_as_p2":       wins_as_p2,
        "games_per_agent":  games_per_agent,
        "N":                N,
    }


def _print_win_rate_table(names, win_rate_matrix, ci_matrix):
    n     = len(names)
    col_w = 22
    pad   = max(len(nm) for nm in names) + 2

    print(f"\n--- P1 Win-Rate Matrix  (row = P1 agent, col = P2 opponent) ---")
    header = " " * pad + "".join(f"{nm:<{col_w}}" for nm in names)
    print(header)

    for i, row_name in enumerate(names):
        row = f"{row_name:<{pad}}"
        for j in range(n):
            if i == j:
                cell = "--"
            else:
                p        = win_rate_matrix[i][j]
                lo, hi   = ci_matrix[i][j]
                cell     = f"{p:.3f} [{lo:.3f},{hi:.3f}]"
            row += f"{cell:<{col_w}}"
        print(row)


def _write_tournament_csv(names, win_rate_matrix, ci_matrix,
                          overall, wins_p1, wins_p2, games_per, N):
    filename = "tournament_results.csv"
    with open(filename, "w", newline="") as f:
        w = csv.writer(f)

        # ── Win-rate matrix ────────────────────────────────────────────────
        w.writerow(["P1 Win-Rate Matrix  (row=P1, col=P2)"])
        w.writerow([""] + names)
        for i, name in enumerate(names):
            row = [name]
            for j in range(len(names)):
                if i == j:
                    row.append("--")
                else:
                    row.append(f"{win_rate_matrix[i][j]:.4f}")
            w.writerow(row)

        w.writerow([])
        w.writerow(["95 % CI Lower Bound"])
        w.writerow([""] + names)
        for i, name in enumerate(names):
            row = [name]
            for j in range(len(names)):
                row.append("--" if i == j else f"{ci_matrix[i][j][0]:.4f}")
            w.writerow(row)

        w.writerow([])
        w.writerow(["95 % CI Upper Bound"])
        w.writerow([""] + names)
        for i, name in enumerate(names):
            row = [name]
            for j in range(len(names)):
                row.append("--" if i == j else f"{ci_matrix[i][j][1]:.4f}")
            w.writerow(row)

        w.writerow([])
        w.writerow(["Overall Win Rates"])
        w.writerow(["Agent", "Win Rate", "CI Low", "CI High",
                    "Wins as P1", "Wins as P2", "Total Games", "N per matchup"])
        for i, name in enumerate(names):
            lo, hi = _ci95(overall[i], games_per)
            w.writerow([
                name, f"{overall[i]:.4f}", f"{lo:.4f}", f"{hi:.4f}",
                wins_p1[i], wins_p2[i], games_per, N,
            ])

    print(f"  Results saved → {filename}")


# ═══════════════════════════════════════════════════════════════════════════════
# Heuristic weight tuning — grid search
# ═══════════════════════════════════════════════════════════════════════════════

def tune_heuristic_weights(
    weight_values: Optional[List[float]] = None,
    N_games: int = 20,
    config: Optional[dict] = None,
    verbose: bool = True,
) -> dict:
    """
    Grid search over (w1, w2, w3, w4) = (w_expected_production, w_resource_need,
    w_diversity, w_blocking) maximising heuristic win rate vs a random opponent.

    Parameters
    ----------
    weight_values : list of float, optional
        Values to test for each weight.  Default [0.5, 1.0, 2.0, 3.0, 4.0].
    N_games : int
        Games per weight configuration (heuristic as P1 vs random as P2).
    config : dict, optional
        Base config (rng_seed used for reproducibility).
    verbose : bool
        Print progress every 50 configs and final top-10 table.

    Returns
    -------
    dict with keys: best_weights, best_win_rate, all_results
    """
    if weight_values is None:
        weight_values = [0.5, 1.0, 2.0, 3.0, 4.0]
    if config is None:
        config = default_config()

    cfg              = dict(config)
    cfg["verbose"]   = False
    cfg["num_players"] = 2

    random_fn   = resolve_agent("random")
    road_w      = cfg.get("heuristic", {}).get("w_road_value", 0.5)

    total_configs = len(weight_values) ** 4
    if verbose:
        print(f"\n{'=' * 56}")
        print(f"  HEURISTIC WEIGHT TUNING")
        print(f"  Weight values  : {weight_values}")
        print(f"  Configurations : {total_configs}")
        print(f"  Games / config : {N_games}")
        print(f"  Total games    : {total_configs * N_games:,}")
        print(f"{'=' * 56}\n")

    base_seed  = cfg.get("rng_seed", 42)
    game_num   = 0
    config_num = 0
    results    = []

    best_win_rate = -1.0
    best_weights  = None

    for w1, w2, w3, w4 in _product(weight_values, repeat=4):
        config_num += 1
        test_cfg   = dict(cfg)
        test_cfg["heuristic"] = {
            "w_expected_production": w1,
            "w_resource_need":       w2,
            "w_diversity":           w3,
            "w_blocking":            w4,
            "w_road_value":          road_w,
        }

        wins = 0
        for _ in range(N_games):
            game_num            += 1
            gc                   = dict(test_cfg)
            gc["rng_seed"]       = base_seed + game_num
            history              = simulate_game([heuristic_agent, random_fn], gc)
            if history["final_state"].winner_id == 1:
                wins += 1

        win_rate = wins / N_games
        results.append({"weights": (w1, w2, w3, w4), "win_rate": win_rate})

        if win_rate > best_win_rate:
            best_win_rate = win_rate
            best_weights  = (w1, w2, w3, w4)

        if verbose and config_num % 50 == 0:
            print(f"  [{config_num:>{len(str(total_configs))}}/{total_configs}]  "
                  f"best so far: {best_weights} → {best_win_rate:.3f}")

    results.sort(key=lambda x: x["win_rate"], reverse=True)

    if verbose:
        print(f"\n--- Top 10 Weight Configurations ---")
        print(f"  {'w_prod':>6} {'w_need':>6} {'w_div':>6} {'w_blk':>6}   win_rate")
        for r in results[:10]:
            w1, w2, w3, w4 = r["weights"]
            print(f"  {w1:>6.1f} {w2:>6.1f} {w3:>6.1f} {w4:>6.1f}   {r['win_rate']:.3f}")
        print(f"\n  Best: w=({best_weights[0]}, {best_weights[1]}, "
              f"{best_weights[2]}, {best_weights[3]})  →  win rate {best_win_rate:.3f}")

    _write_tuning_csv(results)

    return {
        "best_weights":  best_weights,
        "best_win_rate": best_win_rate,
        "all_results":   results,
    }


def _write_tuning_csv(results: list):
    filename = "weight_tuning_results.csv"
    with open(filename, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["w_expected_production", "w_resource_need",
                    "w_diversity", "w_blocking", "win_rate"])
        for r in results:
            w1, w2, w3, w4 = r["weights"]
            w.writerow([w1, w2, w3, w4, f"{r['win_rate']:.4f}"])
    print(f"  Weight tuning results saved → {filename}")


# ═══════════════════════════════════════════════════════════════════════════════
# Quick-start CLI
# ═══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    import sys

    args = sys.argv[1:]
    if not args or args[0] == "tournament":
        agents = args[1:] if len(args) > 1 else ["random", "heuristic", "monte_carlo", "mcts"]
        N      = int(args[0]) if args and args[0].isdigit() else 50
        run_tournament(agents, N=50)
    elif args[0] == "tune":
        tune_heuristic_weights(N_games=20)
    else:
        print("Usage:")
        print("  python tournament.py tournament [agent1 agent2 ...]")
        print("  python tournament.py tune")
