class HeuristicAgent(Agent):
    def choose_action(self, game_state, player_id):
        player = game_state.players[player_id]

        if player.can_afford(BUILD_COSTS["city"]):
            return {"type": "build", "structure": "city"}
        if player.can_afford(BUILD_COSTS["settlement"]):
            return {"type": "build", "structure": "settlement"}

        return {"type": "pass"}
