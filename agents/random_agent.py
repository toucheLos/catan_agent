class RandomAgent(Agent):
    def choose_action(self, game_state, player_id):
        actions = ["build_settlement", "build_city", "pass"]
        return {"type": random.choice(actions)}
