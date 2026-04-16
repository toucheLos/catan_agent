function tournament(numGames)
% TOURNAMENT  Run a full Catan multi-agent experiment across player counts.
%
%   tournament()         — run with default settings (see PARAMS block)
%   tournament(numGames) — override number of games per matchup

%% ========================= PARAMS =========================
PARAMS.numGames       = 50;        % games per matchup
PARAMS.outputDir      = 'outputs'; % relative to working directory
PARAMS.baseSeed       = 1000;      % rngSeed = baseSeed + per-game offset
PARAMS.agents         = {'random','heuristic','monte_carlo','mcts'};
PARAMS.playerCounts   = [2, 3, 4];
PARAMS.rolloutCount   = 15;
PARAMS.rolloutHorizon = 25;
%% =========================================================

if nargin >= 1
    PARAMS.numGames = numGames;
end

timestamp = datestr(now, 'yyyymmdd_HHMMSS');
outDir    = PARAMS.outputDir;
agents    = PARAMS.agents;
nA        = numel(agents);

if ~exist(outDir, 'dir')
    mkdir(outDir);
end

allRawResults = {};
pcDataArr     = cell(numel(PARAMS.playerCounts), 1);

for pcIdx = 1:numel(PARAMS.playerCounts)
    pc = PARAMS.playerCounts(pcIdx);

    fprintf('\n========================================\n');
    fprintf('  PLAYER COUNT: %d\n', pc);
    fprintf('========================================\n');

    matchups = generateMatchups(agents, pc);
    if pc == 4
        matchups = prioritizeMatchups4(matchups, agents);
    end
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
            allRawResults{end+1} = raw; %#ok<AGROW>
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

function matchups = generateMatchups(agents, k)
% All k-multiset combinations of agents (non-decreasing index sequences)
n      = numel(agents);
idxMat = multisetCombinations(n, k);
matchups = cell(size(idxMat, 1), 1);
for i = 1:size(idxMat, 1)
    matchups{i} = agents(idxMat(i, :));
end
end

function C = multisetCombinations(n, k)
% All non-decreasing length-k sequences from 1:n (combinations with repetition)
if k == 1
    C = (1:n)';
    return;
end
C = [];
for v = 1:n
    sub = multisetCombinationsFrom(n, k-1, v);
    C   = [C; repmat(v, size(sub,1), 1), sub]; %#ok<AGROW>
end
end

function C = multisetCombinationsFrom(n, k, minVal)
if k == 1
    C = (minVal:n)';
    return;
end
C = [];
for v = minVal:n
    sub = multisetCombinationsFrom(n, k-1, v);
    C   = [C; repmat(v, size(sub,1), 1), sub]; %#ok<AGROW>
end
end

function matchups = prioritizeMatchups4(matchups, agents)
% Sort: all-different first (score 0), all-same second (score 1), rest last (score 2)
nM     = numel(matchups);
nA     = numel(agents);
scores = zeros(nM, 1);
for i = 1:nM
    u = unique(matchups{i});
    if numel(u) == nA
        scores(i) = 0;
    elseif numel(u) == 1
        scores(i) = 1;
    else
        scores(i) = 2;
    end
end
[~, ord] = sort(scores, 'stable');
matchups  = matchups(ord);
end

%% ===== CONFIG & GAME RUNNER =====

function cfg = buildConfig(PARAMS, pcIdx, m, g)
cfg                          = catan_core('defaultConfig');
cfg.showViz                  = false;
cfg.pauseAfterMove           = false;
cfg.verbose                  = false;
cfg.rngSeed                  = PARAMS.baseSeed + (pcIdx-1)*100000 + (m-1)*1000 + g;
cfg.rolloutCount             = PARAMS.rolloutCount;
cfg.rolloutHorizon           = PARAMS.rolloutHorizon;
cfg.mc.selfRolloutPolicy     = 'heuristic';
cfg.mc.opponentRolloutPolicy = 'random';
end

function [winnerId, vps, totalTurns, isError] = runOneGame(agentFns, cfg, playerNames)
isError    = false;
winnerId   = 0;
vps        = zeros(1, numel(agentFns));
totalTurns = NaN;
try
    history    = catan_core('simulateGame', agentFns, cfg, playerNames);
    fs         = history.finalState;
    totalTurns = fs.turnIndex;
    winnerId   = fs.winnerId;
    for p = 1:numel(agentFns)
        vps(p) = catan_core('computeVP', fs, p);
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
