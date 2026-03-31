import random
from collections import defaultdict
from copy import deepcopy

RESOURCES = ["wood", "brick", "sheep", "wheat", "ore"]

BUILD_COSTS = {
    "road": {"wood": 1, "brick": 1},
    "settlement": {"wood": 1, "brick": 1, "sheep": 1, "wheat": 1},
    "city": {"ore": 3, "wheat": 2}
}

WIN_POINTS = 10