function tournament(numGames)
% TOURNAMENT  Run a full Catan multi-agent experiment across player counts.
%
%   tournament()         — run with default settings (see PARAMS block)
%   tournament(numGames) — override number of games per matchup

%% ========================= PARAMS =========================
PARAMS.numGames       = 50;        % games per matchup
PARAMS.outputDir      = 'outputs'; % relative to working directory
PARAMS.baseSeed       = 1000;      % rngSeed = baseSeed + per-game offset
PARAMS.agents2p       = {'heuristic','monte_carlo','mcts'};
PARAMS.agents4p       = {'random','heuristic','monte_carlo','mcts'};
PARAMS.playerCounts   = [2, 4];
PARAMS.rolloutCount   = 15;
PARAMS.rolloutHorizon = 25;
%% =========================================================

if nargin >= 1
    PARAMS.numGames = numGames;
end

timestamp = datestr(now, 'yyyymmdd_HHMMSS');
outDir    = fullfile(fileparts(mfilename('fullpath')), PARAMS.outputDir);
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

allRawResults = {};
pcDataArr     = cell(numel(PARAMS.playerCounts), 1);

for pcIdx = 1:numel(PARAMS.playerCounts)
    pc = PARAMS.playerCounts(pcIdx);

    if pc == 2
        agents = PARAMS.agents2p;
    else
        agents = PARAMS.agents4p;
    end
    nA = numel(agents);

    fprintf('\n========================================\n');
    fprintf('  PLAYER COUNT: %d\n', pc);
    fprintf('========================================\n');

    matchups = generateMatchups(agents, pc);
    nM = numel(matchups);

    mSumm = initMatchupSummaries(matchups, nA, nM);

    for m = 1:nM
        nP       = numel(matchups{m});
        agentFns = cellfun(@resolveAgent, matchups{m}, 'UniformOutput', false);

        for g = 1:PARAMS.numGames
            fprintf('Player count %d | Matchup %d/%d | Game %d/%d\n', ...
                pc, m, nM, g, PARAMS.numGames);

            cfg = buildConfig(PARAMS, pcIdx, m, g);

            [winnerId, vps, totalTurns, isError] = runOneGame(agentFns, cfg, matchups{m});

            mSumm = accumulateResult(mSumm, m, matchups{m}, agents, ...
                                     winnerId, vps, totalTurns, isError);

            raw.pc           = pc;
            raw.matchup      = mSumm(m).str;
            raw.gameIdx      = g;
            raw.winnerAgent  = getWinnerLabel(matchups{m}, winnerId, isError);
            raw.playerAgents = matchups{m};
            raw.playerVPs    = vps;
            raw.totalTurns   = totalTurns;
            raw.runId        = timestamp;
            allRawResults{end+1} = raw; %#ok<AGROW>
            appendGameResult(raw, outDir);
        end
    end

    printPCSummary(pc, mSumm, agents);

    pcDataArr{pcIdx} = struct('pc', pc, 'matchups', {matchups}, 'mSumm', mSumm);
end

printGlobalSummary(pcDataArr, agents);
writeAllCSVs(pcDataArr, allRawResults, agents, timestamp, outDir);
writeAllPlots(pcDataArr, agents, timestamp, outDir);

fprintf('\nAll outputs saved to: %s/\n', outDir);
end

%% ===== MATCHUP GENERATION =====

function matchups = generateMatchups(agents, pc)
nA = numel(agents);
if pc == 2
    % All unique pairs (no self-play)
    pairs = nchoosek(1:nA, 2);
    matchups = cell(size(pairs, 1), 1);
    for i = 1:size(pairs, 1)
        matchups{i} = agents(pairs(i, :));
    end
else
    % Full roster in one matchup (4-player)
    matchups = {agents};
end
end

%% ===== CONFIG & GAME RUNNER =====

function cfg = buildConfig(PARAMS, pcIdx, m, g)
cfg                          = catan_core('defaultConfig');
cfg.showViz                  = false;
cfg.pauseAfterMove           = false;
cfg.verbose                  = false;
cfg.inspectTurn              = [];
cfg.rngSeed                  = PARAMS.baseSeed + (pcIdx-1)*100000 + (m-1)*1000 + g;
cfg.rolloutCount             = PARAMS.rolloutCount;
cfg.rolloutHorizon           = PARAMS.rolloutHorizon;
cfg.mc.selfRolloutPolicy     = 'random';
cfg.mc.opponentRolloutPolicy = 'random';
end

function [winnerId, vps, totalTurns, isError] = runOneGame(agentFns, cfg, playerNames)
isError    = false;
winnerId   = 0;
nP         = numel(agentFns);
vps        = zeros(1, nP);
totalTurns = NaN;

% Randomize seating order each game
perm              = randperm(nP);
agentFnsShuf      = agentFns(perm);
playerNamesShuf   = playerNames(perm);
invPerm           = zeros(1, nP);
invPerm(perm)     = 1:nP;

try
    history    = catan_core('simulateGame', agentFnsShuf, cfg, playerNamesShuf);
    fs         = history.finalState;
    totalTurns = fs.turnIndex;

    % VPs per shuffled seat → unscramble to original agent order
    vpsSeat = zeros(1, nP);
    for p = 1:nP
        vpsSeat(p) = catan_core('computeVP', fs, p);
    end
    vps = vpsSeat(invPerm);

    % Winner seat (shuffled) → original agent index
    if fs.winnerId > 0
        winnerId = invPerm(fs.winnerId);
    end
catch e
    fprintf('  ERROR in game: %s\n', e.message);
    isError = true;
end
end

%% ===== RESULT ACCUMULATION =====

function mSumm = initMatchupSummaries(matchups, nA, nM)
mSumm = struct( ...
    'str',    repmat({''}, nM, 1), ...
    'agents', repmat({{}}, nM, 1), ...
    'wins',   num2cell(zeros(nM, nA), 2), ...
    'seats',  num2cell(zeros(nM, nA), 2), ...
    'vpAll',  repmat({cell(1,nA)}, nM, 1), ...
    'lengths', repmat({[]}, nM, 1), ...
    'games',  repmat({0}, nM, 1));
for m = 1:nM
    mSumm(m).str    = strjoin(matchups{m}, '+');
    mSumm(m).agents = matchups{m};
    mSumm(m).vpAll  = cell(1, nA);
    for a = 1:nA
        mSumm(m).vpAll{a} = [];
    end
end
end

function mSumm = accumulateResult(mSumm, m, matchupAgents, agents, ...
                                   winnerId, vps, totalTurns, isError)
mSumm(m).games = mSumm(m).games + 1;
if ~isnan(totalTurns)
    mSumm(m).lengths = [mSumm(m).lengths, totalTurns];
end
for p = 1:numel(matchupAgents)
    aIdx = find(strcmp(agents, matchupAgents{p}), 1);
    mSumm(m).seats(aIdx) = mSumm(m).seats(aIdx) + 1;
    if ~isError
        mSumm(m).vpAll{aIdx}(end+1) = vps(p);
    end
end
if winnerId > 0 && ~isError
    wIdx = find(strcmp(agents, matchupAgents{winnerId}), 1);
    mSumm(m).wins(wIdx) = mSumm(m).wins(wIdx) + 1;
end
end

function label = getWinnerLabel(matchupAgents, winnerId, isError)
if isError
    label = 'error';
elseif winnerId == 0
    label = 'draw';
else
    label = matchupAgents{winnerId};
end
end

%% ===== CONSOLE OUTPUT =====

function printPCSummary(pc, mSumm, agents)
nA       = numel(agents);
totWins  = zeros(1, nA);
totSeats = zeros(1, nA);
totVPSum = zeros(1, nA);
totVPCnt = zeros(1, nA);
totLen   = [];
for m = 1:numel(mSumm)
    totWins  = totWins  + mSumm(m).wins;
    totSeats = totSeats + mSumm(m).seats;
    for a = 1:nA
        totVPSum(a) = totVPSum(a) + sum(mSumm(m).vpAll{a});
        totVPCnt(a) = totVPCnt(a) + numel(mSumm(m).vpAll{a});
    end
    totLen = [totLen, mSumm(m).lengths]; %#ok<AGROW>
end
totLen = totLen(~isnan(totLen));
avgLen = 0;
if ~isempty(totLen), avgLen = mean(totLen); end

fprintf('\n--- Summary: %d-player ---\n', pc);
fprintf('%-15s %6s %6s %8s %7s %10s\n', ...
    'Agent','Wins','Games','WinRate','AvgVP','AvgLength');
fprintf('%s\n', repmat('-', 1, 58));
for a = 1:nA
    wr = 0; avgVP = 0;
    if totSeats(a) > 0, wr    = totWins(a)  / totSeats(a); end
    if totVPCnt(a) > 0, avgVP = totVPSum(a) / totVPCnt(a); end
    fprintf('%-15s %6d %6d %8.3f %7.2f %10.1f\n', ...
        agents{a}, totWins(a), totSeats(a), wr, avgVP, avgLen);
end
end

function printGlobalSummary(pcDataArr, agents)
nA       = numel(agents);
totWins  = zeros(1, nA);
totSeats = zeros(1, nA);
totVPSum = zeros(1, nA);
totVPCnt = zeros(1, nA);
totLen   = [];
for pcIdx = 1:numel(pcDataArr)
    mSumm = pcDataArr{pcIdx}.mSumm;
    for m = 1:numel(mSumm)
        totWins  = totWins  + mSumm(m).wins;
        totSeats = totSeats + mSumm(m).seats;
        for a = 1:nA
            totVPSum(a) = totVPSum(a) + sum(mSumm(m).vpAll{a});
            totVPCnt(a) = totVPCnt(a) + numel(mSumm(m).vpAll{a});
        end
        totLen = [totLen, mSumm(m).lengths]; %#ok<AGROW>
    end
end
totLen = totLen(~isnan(totLen));
avgLen = 0;
if ~isempty(totLen), avgLen = mean(totLen); end

fprintf('\n========================================\n');
fprintf('  GLOBAL SUMMARY (all player counts)\n');
fprintf('========================================\n');
fprintf('%-15s %6s %6s %8s %7s %10s\n', ...
    'Agent','Wins','Games','WinRate','AvgVP','AvgLength');
fprintf('%s\n', repmat('-', 1, 58));
for a = 1:nA
    wr = 0; avgVP = 0;
    if totSeats(a) > 0, wr    = totWins(a)  / totSeats(a); end
    if totVPCnt(a) > 0, avgVP = totVPSum(a) / totVPCnt(a); end
    fprintf('%-15s %6d %6d %8.3f %7.2f %10.1f\n', ...
        agents{a}, totWins(a), totSeats(a), wr, avgVP, avgLen);
end
end

%% ===== CSV WRITING =====

function writeAllCSVs(pcDataArr, allRawResults, agents, timestamp, outDir)
writeWinRatesCSV(pcDataArr, agents, timestamp, outDir);
writeVPDistCSV(pcDataArr, agents, timestamp, outDir);
writeGameLengthCSV(pcDataArr, timestamp, outDir);
writeRawResultsCSV(allRawResults, timestamp, outDir);
end

function writeWinRatesCSV(pcDataArr, agents, timestamp, outDir)
fpath = fullfile(outDir, [timestamp '_win_rates.csv']);
fid   = fopen(fpath, 'w');
fprintf(fid, 'player_count,matchup,agent,wins,games,win_rate\n');
for pcIdx = 1:numel(pcDataArr)
    pc    = pcDataArr{pcIdx}.pc;
    mSumm = pcDataArr{pcIdx}.mSumm;
    for m = 1:numel(mSumm)
        for a = 1:numel(agents)
            wr = 0;
            if mSumm(m).seats(a) > 0
                wr = mSumm(m).wins(a) / mSumm(m).seats(a);
            end
            fprintf(fid, '%d,%s,%s,%d,%d,%.4f\n', ...
                pc, mSumm(m).str, agents{a}, ...
                mSumm(m).wins(a), mSumm(m).seats(a), wr);
        end
    end
end
fclose(fid);
fprintf('Wrote: %s\n', fpath);
end

function writeVPDistCSV(pcDataArr, agents, timestamp, outDir)
fpath = fullfile(outDir, [timestamp '_vp_distribution.csv']);
fid   = fopen(fpath, 'w');
fprintf(fid, 'player_count,matchup,agent,vp_mean,vp_std,vp_min,vp_max\n');
for pcIdx = 1:numel(pcDataArr)
    pc    = pcDataArr{pcIdx}.pc;
    mSumm = pcDataArr{pcIdx}.mSumm;
    for m = 1:numel(mSumm)
        for a = 1:numel(agents)
            vps = mSumm(m).vpAll{a};
            if isempty(vps), continue; end
            fprintf(fid, '%d,%s,%s,%.4f,%.4f,%d,%d\n', ...
                pc, mSumm(m).str, agents{a}, ...
                mean(vps), std(vps), min(vps), max(vps));
        end
    end
end
fclose(fid);
fprintf('Wrote: %s\n', fpath);
end

function writeGameLengthCSV(pcDataArr, timestamp, outDir)
fpath = fullfile(outDir, [timestamp '_game_length.csv']);
fid   = fopen(fpath, 'w');
fprintf(fid, 'player_count,matchup,turns_mean,turns_std,turns_min,turns_max\n');
for pcIdx = 1:numel(pcDataArr)
    pc    = pcDataArr{pcIdx}.pc;
    mSumm = pcDataArr{pcIdx}.mSumm;
    for m = 1:numel(mSumm)
        lens = mSumm(m).lengths;
        lens = lens(~isnan(lens));
        if isempty(lens), continue; end
        fprintf(fid, '%d,%s,%.2f,%.2f,%d,%d\n', ...
            pc, mSumm(m).str, ...
            mean(lens), std(lens), min(lens), max(lens));
    end
end
fclose(fid);
fprintf('Wrote: %s\n', fpath);
end

function writeRawResultsCSV(allRawResults, timestamp, outDir)
fpath = fullfile(outDir, [timestamp '_raw_results.csv']);
fid   = fopen(fpath, 'w');
fprintf(fid, 'player_count,matchup,game_index,winner_agent,');
fprintf(fid, 'p1_agent,p1_vp,p2_agent,p2_vp,p3_agent,p3_vp,p4_agent,p4_vp,total_turns\n');
for i = 1:numel(allRawResults)
    r  = allRawResults{i};
    nP = numel(r.playerAgents);

    pA = [r.playerAgents, {'','','',''}];
    pV = [r.playerVPs,    zeros(1, 4-nP)];

    % Format VP strings (blank for non-existent players)
    vpStr = cell(1, 4);
    for p = 1:4
        if p <= nP
            vpStr{p} = sprintf('%d', pV(p));
        else
            vpStr{p} = '';
        end
    end

    turnStr = '';
    if ~isnan(r.totalTurns)
        turnStr = sprintf('%d', r.totalTurns);
    end

    fprintf(fid, '%d,%s,%d,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n', ...
        r.pc, r.matchup, r.gameIdx, r.winnerAgent, ...
        pA{1}, vpStr{1}, pA{2}, vpStr{2}, ...
        pA{3}, vpStr{3}, pA{4}, vpStr{4}, ...
        turnStr);
end
fclose(fid);
fprintf('Wrote: %s\n', fpath);
end

%% ===== PLOTS =====

function writeAllPlots(pcDataArr, agents, timestamp, outDir)
for pcIdx = 1:numel(pcDataArr)
    pcData = pcDataArr{pcIdx};
    pc     = pcData.pc;
    plotWinRates(pcData, agents, timestamp, outDir, pc);
    plotVPBoxplot(pcData, agents, timestamp, outDir, pc);
    plotGameLength(pcData, timestamp, outDir, pc);
end

% 4-player heatmap
for pcIdx = 1:numel(pcDataArr)
    if pcDataArr{pcIdx}.pc == 4
        plotHeatmap4p(pcDataArr{pcIdx}, agents, timestamp, outDir);
        break;
    end
end
end

function plotWinRates(pcData, agents, timestamp, outDir, pc)
mSumm = pcData.mSumm;
nM    = numel(mSumm);
nA    = numel(agents);

winRateMat    = zeros(nM, nA);
matchupLabels = cell(nM, 1);
for m = 1:nM
    matchupLabels{m} = mSumm(m).str;
    for a = 1:nA
        if mSumm(m).seats(a) > 0
            winRateMat(m,a) = mSumm(m).wins(a) / mSumm(m).seats(a);
        end
    end
end

figW = max(900, nM * 55 + 200);
fig  = figure('Visible','off','Position',[100 100 figW 450]);
bar(winRateMat);
set(gca, 'XTick', 1:nM, 'XTickLabel', matchupLabels, ...
         'XTickLabelRotation', 45, 'TickLabelInterpreter', 'none');
legend(agents, 'Location','northeast', 'Interpreter','none');
ylabel('Win Rate (per seat)');
title(sprintf('%d-Player Win Rates by Matchup', pc));
ylim([0 1]);
grid on;
tight_layout_hack(fig);
fpath = fullfile(outDir, sprintf('%s_win_rate_%dp.png', timestamp, pc));
saveas(fig, fpath);
close(fig);
fprintf('Wrote: %s\n', fpath);
end

function plotVPBoxplot(pcData, agents, timestamp, outDir, pc)
mSumm = pcData.mSumm;
nA    = numel(agents);

vpVals  = [];
vpGroup = {};
for m = 1:numel(mSumm)
    for a = 1:nA
        vps = mSumm(m).vpAll{a};
        if ~isempty(vps)
            vpVals  = [vpVals, vps]; %#ok<AGROW>
            vpGroup = [vpGroup, repmat(agents(a), 1, numel(vps))]; %#ok<AGROW>
        end
    end
end

if isempty(vpVals)
    return;
end

fig = figure('Visible','off','Position',[100 100 600 420]);
boxplot(vpVals, vpGroup, 'GroupOrder', agents);
ylabel('Final VP');
title(sprintf('%d-Player VP Distribution by Agent', pc));
grid on;
fpath = fullfile(outDir, sprintf('%s_vp_boxplot_%dp.png', timestamp, pc));
saveas(fig, fpath);
close(fig);
fprintf('Wrote: %s\n', fpath);
end

function plotGameLength(pcData, timestamp, outDir, pc)
mSumm      = pcData.mSumm;
allLengths = [];
for m = 1:numel(mSumm)
    allLengths = [allLengths, mSumm(m).lengths]; %#ok<AGROW>
end
allLengths = allLengths(~isnan(allLengths));

if isempty(allLengths)
    return;
end

fig = figure('Visible','off','Position',[100 100 600 400]);
histogram(allLengths, 20);
xlabel('Total Turns');
ylabel('Count');
title(sprintf('%d-Player Game Length Distribution', pc));
grid on;
fpath = fullfile(outDir, sprintf('%s_game_length_%dp.png', timestamp, pc));
saveas(fig, fpath);
close(fig);
fprintf('Wrote: %s\n', fpath);
end

function plotHeatmap4p(pcData4, agents, timestamp, outDir)
mSumm = pcData4.mSumm;
nA    = numel(agents);
nM    = numel(mSumm);

winRateMat    = zeros(nA, nM);
matchupLabels = cell(nM, 1);
for m = 1:nM
    matchupLabels{m} = mSumm(m).str;
    for a = 1:nA
        if mSumm(m).seats(a) > 0
            winRateMat(a,m) = mSumm(m).wins(a) / mSumm(m).seats(a);
        end
    end
end

figW = max(1200, nM * 30 + 200);
fig  = figure('Visible','off','Position',[100 100 figW 320]);
imagesc(winRateMat, [0 1]);
colorbar;
colormap(hot);
set(gca, 'XTick', 1:nM, 'XTickLabel', matchupLabels, ...
         'XTickLabelRotation', 45, 'TickLabelInterpreter', 'none', ...
         'YTick', 1:nA, 'YTickLabel', agents, 'YTickLabelInterpreter', 'none');
title('4-Player Win Rate Heatmap (per seat)');
xlabel('Matchup');
ylabel('Agent');
tight_layout_hack(fig);
fpath = fullfile(outDir, sprintf('%s_heatmap_4p.png', timestamp));
saveas(fig, fpath);
close(fig);
fprintf('Wrote: %s\n', fpath);
end

function tight_layout_hack(fig)
% Apply tight layout to leave room for rotated x-tick labels
set(fig, 'Units','normalized');
ax = findall(fig, 'Type','axes');
for i = 1:numel(ax)
    set(ax(i), 'Units','normalized');
end
try
    % R2020a+
    for i = 1:numel(ax)
        ax(i).Position(2) = 0.25;
        ax(i).Position(4) = 0.60;
    end
catch
end
end

%% ===== INCREMENTAL SAVE =====

function appendGameResult(raw, outDir)
if ~exist(outDir, 'dir'), mkdir(outDir); end
fpath = fullfile(outDir, 'tournament_all_results.csv');
isNew = ~exist(fpath, 'file');
fid   = fopen(fpath, 'a');
if fid == -1
    warning('tournament:appendGameResult', 'Could not open %s for writing.', fpath);
    return;
end
if isNew
    fprintf(fid, 'run_id,player_count,matchup,game_index,winner_agent,p1_agent,p1_vp,p2_agent,p2_vp,p3_agent,p3_vp,p4_agent,p4_vp,total_turns\n');
end
nP = numel(raw.playerAgents);
pA = [raw.playerAgents, {'','','',''}];
pV = [raw.playerVPs,    zeros(1, 4-nP)];
vpStr = cell(1, 4);
for p = 1:4
    if p <= nP, vpStr{p} = sprintf('%d', pV(p));
    else,       vpStr{p} = ''; end
end
turnStr = '';
if ~isnan(raw.totalTurns), turnStr = sprintf('%d', raw.totalTurns); end
fprintf(fid, '%s,%d,%s,%d,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n', ...
    raw.runId, raw.pc, raw.matchup, raw.gameIdx, raw.winnerAgent, ...
    pA{1}, vpStr{1}, pA{2}, vpStr{2}, ...
    pA{3}, vpStr{3}, pA{4}, vpStr{4}, turnStr);
fclose(fid);
end

%% ===== AGENT RESOLVER =====

function fn = resolveAgent(name)
switch lower(name)
    case 'random',      fn = @agent_random;
    case 'heuristic',   fn = @agent_heuristic;
    case 'monte_carlo', fn = @agent_montecarlo;
    case 'mcts',        fn = @agent_mcts;
    otherwise
        error('Unknown agent: %s. Choose: random, heuristic, monte_carlo, mcts.', name);
end
end
