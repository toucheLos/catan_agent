class PlayerState:
    def __init__(self, player_id):
        self.id = player_id
        self.resources = defaultdict(int)
        self.victory_points = 0

    def can_afford(self, cost):
        return all(self.resources[r] >= cost[r] for r in cost)

    def pay(self, cost):
        for r in cost:
            self.resources[r] -= cost[r]
