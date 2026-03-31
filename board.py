"""
board.py — Catan board data structures and procedural board generation.

Produces a standard 19-hex, 54-vertex, ~72-edge board using a radius-2 axial
hex grid with pointy-top orientation, matching the MATLAB catan_core.m layout.

Board objects are *immutable* after creation.  Ownership (vertex_owners,
edge_owners) is tracked separately in GameState so state copies are fast.
"""

import math
import random as _random
from typing import Dict, List, Tuple

# ── Resource / number pools (matches standard Catan) ─────────────────────────

RESOURCE_BAG: List[str] = (
    ["wood"]  * 4 +
    ["brick"] * 3 +
    ["sheep"] * 4 +
    ["wheat"] * 4 +
    ["ore"]   * 3 +
    ["desert"]
)  # 19 tiles total

NUMBER_BAG: List[int] = [2, 12, 3, 3, 4, 4, 5, 5, 6, 6, 8, 8, 9, 9, 10, 10, 11, 11]
# 18 tokens (desert gets 7, excluded from this pool)

# Probability of rolling n with two d6
DICE_PROBS: Dict[int, float] = {
    n: w / 36
    for n, w in zip(range(2, 13), [1, 2, 3, 4, 5, 6, 5, 4, 3, 2, 1])
}


def dice_probability(n: int) -> float:
    """Probability that two d6 sum to n (0 if outside 2–12)."""
    return DICE_PROBS.get(n, 0.0)


# ── Data classes (plain objects, no dataclass overhead in hot paths) ──────────

class Hex:
    """One of the 19 hex tiles."""
    __slots__ = ("hid", "resource_type", "dice_number", "vertex_ids", "center")

    def __init__(self, hid: int, resource_type: str, dice_number: int,
                 vertex_ids: List[int], center: Tuple[float, float]):
        self.hid          = hid
        self.resource_type = resource_type
        self.dice_number  = dice_number
        self.vertex_ids   = vertex_ids   # 6 vertex IDs in corner order
        self.center       = center       # (x, y) Cartesian


class Vertex:
    """One of the 54 board vertices (intersection of up to 3 hexes)."""
    __slots__ = ("vid", "pos", "adj_hex_ids", "adj_vertex_ids")

    def __init__(self, vid: int, pos: Tuple[float, float],
                 adj_hex_ids: List[int], adj_vertex_ids: List[int]):
        self.vid            = vid
        self.pos            = pos             # (x, y)
        self.adj_hex_ids    = adj_hex_ids     # 1–3 adjacent hex IDs
        self.adj_vertex_ids = adj_vertex_ids  # 2–3 adjacent vertex IDs


class Edge:
    """One directed-pair edge between two adjacent vertices (road slot)."""
    __slots__ = ("eid", "v1", "v2")

    def __init__(self, eid: int, v1: int, v2: int):
        self.eid = eid
        self.v1  = v1   # always the smaller vertex ID
        self.v2  = v2   # always the larger vertex ID


class Board:
    """
    Immutable board topology.

    Attributes
    ----------
    hexes    : list of Hex,   indexed 0..18
    vertices : list of Vertex, indexed 0..53
    edges    : list of Edge,  indexed 0..N_edges-1

    vertex_edges : dict[vid -> list[eid]]   all edges incident to a vertex
    vp_to_edge   : dict[(v1,v2) -> eid]     edge lookup by sorted vertex pair
    """

    def __init__(self, hexes: List[Hex], vertices: List[Vertex], edges: List[Edge]):
        self.hexes    = hexes
        self.vertices = vertices
        self.edges    = edges

        self.vertex_edges: Dict[int, List[int]] = {v.vid: [] for v in vertices}
        self.vp_to_edge:   Dict[Tuple[int, int], int] = {}

        for e in edges:
            self.vertex_edges[e.v1].append(e.eid)
            self.vertex_edges[e.v2].append(e.eid)
            self.vp_to_edge[(e.v1, e.v2)] = e.eid
            self.vp_to_edge[(e.v2, e.v1)] = e.eid


# ── Board generation ──────────────────────────────────────────────────────────

def _axial_coords_radius2() -> List[Tuple[int, int]]:
    """19 axial (q, r) coordinates for a radius-2 hex grid."""
    R = 2
    return [
        (q, r)
        for q in range(-R, R + 1)
        for r in range(-R, R + 1)
        if max(abs(q), abs(r), abs(-q - r)) <= R
    ]


def _axial_to_cartesian(q: int, r: int, scale: float = 1.0) -> Tuple[float, float]:
    """Pointy-top axial → Cartesian (matches MATLAB: x=√3*(q+r/2), y=1.5*r)."""
    x = scale * math.sqrt(3) * (q + r / 2)
    y = scale * 1.5 * r
    return (x, y)


def _vertex_key(x: float, y: float) -> str:
    """Stable deduplication key from position rounded to 6 decimal places."""
    return f"{x:.6f}_{y:.6f}"


def create_board() -> Board:
    """
    Build a fully randomised Catan board.

    Call ``random.seed(s)`` *before* this function to get reproducible boards.
    (simulate_game does this automatically via config['rng_seed'].)
    """
    axial    = _axial_coords_radius2()
    n_hexes  = len(axial)           # 19
    scale    = 1.0
    # Pointy-top corner angles: 30°, 90°, 150°, 210°, 270°, 330°
    angles   = [math.radians(30 + k * 60) for k in range(6)]

    # Shuffle resources and number tokens
    resources = RESOURCE_BAG.copy()
    _random.shuffle(resources)

    numbers = NUMBER_BAG.copy()
    _random.shuffle(numbers)

    # Assign dice numbers (desert always → 7)
    dice_numbers: List[int] = []
    num_idx = 0
    for h in range(n_hexes):
        if resources[h] == "desert":
            dice_numbers.append(7)
        else:
            dice_numbers.append(numbers[num_idx])
            num_idx += 1

    # ── Build vertices (deduplicate by position) ──────────────────────────────
    vertex_map:       Dict[str, int]       = {}   # key → vid
    vertex_positions: List[Tuple[float, float]] = []
    vertex_adj_hexes: Dict[int, List[int]]  = {}   # vid → [hex ids]
    hex_vertex_ids:   List[List[int]]       = []   # hid → [6 vids]

    for h, (q, r) in enumerate(axial):
        cx, cy    = _axial_to_cartesian(q, r, scale)
        h_vids: List[int] = []

        for angle in angles:
            px  = round(cx + scale * math.cos(angle), 6)
            py  = round(cy + scale * math.sin(angle), 6)
            key = _vertex_key(px, py)

            if key not in vertex_map:
                vid = len(vertex_positions)
                vertex_map[key]       = vid
                vertex_positions.append((px, py))
                vertex_adj_hexes[vid] = [h]
            else:
                vid = vertex_map[key]
                vertex_adj_hexes[vid].append(h)

            h_vids.append(vid)

        hex_vertex_ids.append(h_vids)

    n_vertices = len(vertex_positions)

    # ── Vertex–vertex adjacency (consecutive corners within each hex) ─────────
    adj_sets: Dict[int, set] = {v: set() for v in range(n_vertices)}
    for h in range(n_hexes):
        ids = hex_vertex_ids[h]
        for k in range(6):
            a, b = ids[k], ids[(k + 1) % 6]
            adj_sets[a].add(b)
            adj_sets[b].add(a)

    # ── Build Vertex objects ──────────────────────────────────────────────────
    vertices: List[Vertex] = [
        Vertex(
            vid=v,
            pos=vertex_positions[v],
            adj_hex_ids=sorted(vertex_adj_hexes[v]),
            adj_vertex_ids=sorted(adj_sets[v]),
        )
        for v in range(n_vertices)
    ]

    # ── Build Hex objects ─────────────────────────────────────────────────────
    hexes: List[Hex] = [
        Hex(
            hid=h,
            resource_type=resources[h],
            dice_number=dice_numbers[h],
            vertex_ids=hex_vertex_ids[h],
            center=_axial_to_cartesian(q, r, scale),
        )
        for h, (q, r) in enumerate(axial)
    ]

    # ── Build Edge objects (unique adjacent-vertex pairs) ─────────────────────
    edge_set:  set         = set()
    edges:     List[Edge]  = []

    for h in range(n_hexes):
        ids = hex_vertex_ids[h]
        for k in range(6):
            a, b = ids[k], ids[(k + 1) % 6]
            pair = (min(a, b), max(a, b))
            if pair not in edge_set:
                edge_set.add(pair)
                edges.append(Edge(eid=len(edges), v1=pair[0], v2=pair[1]))

    return Board(hexes, vertices, edges)
