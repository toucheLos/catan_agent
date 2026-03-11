function action = agent_random(~, legalActions, ~, ~)
%AGENT_RANDOM Uniform random policy over legal actions.

idx = randi(numel(legalActions));
action = legalActions(idx);

end
