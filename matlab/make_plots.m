function make_plots()
%MAKE_PLOTS  Reads all result CSVs from outputs/ and generates 4 presentation plots.

%% --- Setup ---
scriptDir = fileparts(mfilename('fullpath'));
outputDir = fullfile(scriptDir, 'outputs');
csvFiles  = dir(fullfile(outputDir, '*.csv'));
timestamp = datestr(now, 'yyyymmdd_HHMMSS');

agents      = {'random','heuristic','monte_carlo','mcts'};
agentColors = [0.40 0.60 0.80;
               0.30 0.70 0.40;
               0.90 0.60 0.20;
               0.70 0.30 0.50];
nA = numel(agents);

%% --- Parse all CSVs ---
allRows = {};
for fi = 1:numel(csvFiles)
    fid = fopen(fullfile(outputDir, csvFiles(fi).name), 'r');
    if fid < 0, continue; end
    fgetl(fid); % skip header
    while ~feof(fid)
        raw = fgetl(fid);
        if ~ischar(raw), continue; end
        line = strtrim(strrep(raw, char(13), ''));
        if isempty(line), continue; end
        p = strsplit(line, ',');
        if numel(p) < 14, continue; end
        row.player_count = str2double(p{2});
        row.winner_agent = strtrim(p{5});
        row.p1_agent = strtrim(p{6});  row.p1_vp = str2double(p{7});
        row.p2_agent = strtrim(p{8});  row.p2_vp = str2double(p{9});
        row.p3_agent = strtrim(p{10}); row.p3_vp = str2double(p{11});
        row.p4_agent = strtrim(p{12}); row.p4_vp = str2double(p{13});
        row.total_turns = str2double(p{14});
        allRows{end+1} = row; %#ok<AGROW>
    end
    fclose(fid);
end

rows2 = allRows(logical(cellfun(@(r) r.player_count == 2, allRows)));
rows4 = allRows(logical(cellfun(@(r) r.player_count == 4, allRows)));
n4    = numel(rows4);

%% =========================================================================
%% PLOT 1 — 1v1 Pairwise Win Rate Heatmap
%% =========================================================================

winCounts  = zeros(nA);
gameCounts = zeros(nA);
for ri = 1:numel(rows2)
    r  = rows2{ri};
    ii = aIdx(agents, r.p1_agent);
    jj = aIdx(agents, r.p2_agent);
    wi = aIdx(agents, r.winner_agent);
    if ii==0 || jj==0 || wi==0, continue; end
    gameCounts(ii,jj) = gameCounts(ii,jj) + 1;
    gameCounts(jj,ii) = gameCounts(jj,ii) + 1;
    if wi == ii
        winCounts(ii,jj) = winCounts(ii,jj) + 1;
    else
        winCounts(jj,ii) = winCounts(jj,ii) + 1;
    end
end

winRates = NaN(nA);
for i = 1:nA
    for j = 1:nA
        if gameCounts(i,j) > 0
            winRates(i,j) = winCounts(i,j) / gameCounts(i,j);
        end
    end
end

cm_heat = parula(100);
grayVal = [0.82 0.82 0.82];
imgRGB  = zeros(nA, nA, 3);
for i = 1:nA
    for j = 1:nA
        if i == j || isnan(winRates(i,j))
            imgRGB(i,j,:) = grayVal;
        else
            ci = max(1, min(100, round(winRates(i,j)*99)+1));
            imgRGB(i,j,:) = cm_heat(ci,:);
        end
    end
end

fig1 = figure('Position',[0 0 700 600],'Color','w');
ax1  = axes(fig1);
hold(ax1,'on');
image(ax1, imgRGB);

for k = 0.5:1:nA+0.5
    plot(ax1, [0.5 nA+0.5], [k k], '-w', 'LineWidth',1.2);
    plot(ax1, [k k], [0.5 nA+0.5], '-w', 'LineWidth',1.2);
end

for i = 1:nA
    for j = 1:nA
        if i == j || isnan(winRates(i,j))
            text(ax1, j, i, '—', 'HorizontalAlignment','center', ...
                'VerticalAlignment','middle','FontSize',13,'Color',[0.45 0.45 0.45]);
        else
            text(ax1, j, i, sprintf('%.2f', winRates(i,j)), ...
                'HorizontalAlignment','center','VerticalAlignment','middle', ...
                'FontSize',13,'FontWeight','bold','Color','k');
        end
    end
end

set(ax1,'XTick',1:nA,'XTickLabel',agents,'YTick',1:nA,'YTickLabel',agents, ...
    'FontSize',12,'Box','off','XAxisLocation','top','TickDir','out', ...
    'XLim',[0.5 nA+0.5],'YLim',[0.5 nA+0.5]);
xlabel(ax1,'Opponent','FontSize',13);
ylabel(ax1,'Agent (row)','FontSize',13);
title(ax1,'1v1 Pairwise Win Rate','FontSize',14,'FontWeight','bold');

print(fig1, fullfile(outputDir,['PRESENTATION_' timestamp '_plot1_heatmap.png']), '-dpng','-r150');
close(fig1);
fprintf('Plot 1 saved.\n');

%% =========================================================================
%% PLOT 2 — 4-Player Win Rate with 95% CI
%% =========================================================================

wins4 = zeros(1,nA);
for ri = 1:n4
    wi = aIdx(agents, rows4{ri}.winner_agent);
    if wi > 0, wins4(wi) = wins4(wi) + 1; end
end
wr4 = wins4 / max(n4, 1);

fig2 = figure('Position',[0 0 700 550],'Color','w');
ax2  = axes(fig2);
hold(ax2,'on');
for i = 1:nA
    bar(ax2, i, wr4(i), 0.6, 'FaceColor',agentColors(i,:),'EdgeColor','none');
end
yline(ax2, 0.25, '--k','LineWidth',1.2,'Label','Chance (0.25)', ...
    'LabelHorizontalAlignment','right','FontSize',11);
for i = 1:nA
    if wr4(i) > 0
        text(ax2, i, wr4(i)+0.018, sprintf('%.1f%%',wr4(i)*100), ...
            'HorizontalAlignment','center','FontSize',11,'FontWeight','bold');
    end
end
set(ax2,'XTick',1:nA,'XTickLabel',agents,'FontSize',12,'Box','off', ...
    'YLim',[0 0.6],'GridAlpha',0.25,'TickDir','out');
grid(ax2,'on');
ylabel(ax2,'Win Rate','FontSize',13);
title(ax2,sprintf('4-Player Win Rate (n=%d games)',n4),'FontSize',14,'FontWeight','bold');

print(fig2, fullfile(outputDir,['PRESENTATION_' timestamp '_plot2_4p_winrate.png']), '-dpng','-r150');
close(fig2);
fprintf('Plot 2 saved.\n');

%% =========================================================================
%% PLOT 3 — VP Distribution (1v1 and 4-player side by side)
%% =========================================================================

vp2 = cell(1,nA); for i=1:nA, vp2{i}=[]; end
vp4 = cell(1,nA); for i=1:nA, vp4{i}=[]; end

for ri = 1:numel(rows2)
    r = rows2{ri};
    for slot = 1:2
        if slot==1, ag=r.p1_agent; vp=r.p1_vp;
        else,       ag=r.p2_agent; vp=r.p2_vp; end
        ai = aIdx(agents,ag);
        if ai>0 && ~isnan(vp), vp2{ai}(end+1)=vp; end
    end
end
for ri = 1:n4
    r   = rows4{ri};
    ags = {r.p1_agent,r.p2_agent,r.p3_agent,r.p4_agent};
    vps = [r.p1_vp, r.p2_vp, r.p3_vp, r.p4_vp];
    for slot = 1:4
        ai = aIdx(agents, ags{slot});
        if ai>0 && ~isnan(vps(slot)), vp4{ai}(end+1)=vps(slot); end
    end
end

fig3     = figure('Position',[0 0 1100 500],'Color','w');
spTitles = {'1v1 VP Distribution','4-Player VP Distribution'};
vpSets   = {vp2, vp4};

for sp = 1:2
    subplot(1,2,sp);
    ax3    = gca;
    vpData = vpSets{sp};
    allVP  = []; groupNums = []; gLabels = {}; gColors = [];
    gNum   = 0;
    for i = 1:nA
        if isempty(vpData{i}), continue; end
        gNum      = gNum + 1;
        allVP     = [allVP,     vpData{i}(:)']; %#ok<AGROW>
        groupNums = [groupNums, repmat(gNum, 1, numel(vpData{i}))]; %#ok<AGROW>
        gLabels{end+1} = agents{i}; %#ok<AGROW>
        gColors   = [gColors; agentColors(i,:)]; %#ok<AGROW>
    end
    if isempty(allVP)
        title(ax3,spTitles{sp},'FontSize',14,'FontWeight','bold'); continue;
    end
    boxplot(ax3, allVP(:), groupNums(:), 'Symbol','r+', 'Colors', gColors);
    set(ax3,'XTick',1:numel(gLabels),'XTickLabel',gLabels, ...
        'FontSize',12,'Box','off','GridAlpha',0.25,'TickDir','out');
    grid(ax3,'on');
    ylabel(ax3,'Final VP','FontSize',13);
    title(ax3,spTitles{sp},'FontSize',14,'FontWeight','bold');
end

print(fig3, fullfile(outputDir,['PRESENTATION_' timestamp '_plot3_vp_dist.png']), '-dpng','-r150');
close(fig3);
fprintf('Plot 3 saved.\n');

%% =========================================================================
%% PLOT 4 — Game Length Distribution
%% =========================================================================

turns2 = cellfun(@(r) r.total_turns, rows2);
turns4 = cellfun(@(r) r.total_turns, rows4);
turns2 = turns2(~isnan(turns2) & turns2>0);
turns4 = turns4(~isnan(turns4) & turns4>0);
mean2  = mean(turns2);
mean4  = mean(turns4);

fig4  = figure('Position',[0 0 700 500],'Color','w');
ax4   = axes(fig4);
hold(ax4,'on');
edges = linspace(0,300,21);
histogram(ax4, turns2, edges, 'FaceColor',[0.25 0.45 0.80],'FaceAlpha',0.6, ...
    'EdgeColor','none','DisplayName','2-player');
histogram(ax4, turns4, edges, 'FaceColor',[0.95 0.55 0.15],'FaceAlpha',0.6, ...
    'EdgeColor','none','DisplayName','4-player');
xline(ax4, mean2, '--b','LineWidth',1.5, ...
    'Label',sprintf('2p mean: %dtu',round(mean2)), ...
    'LabelHorizontalAlignment','right','FontSize',11);
xline(ax4, mean4, '--','Color',[0.85 0.40 0.00],'LineWidth',1.5, ...
    'Label',sprintf('4p mean: %dtu',round(mean4)), ...
    'LabelHorizontalAlignment','right','FontSize',11);
set(ax4,'FontSize',12,'Box','off','GridAlpha',0.25,'TickDir','out');
grid(ax4,'on');
xlabel(ax4,'Total Turns','FontSize',13);
ylabel(ax4,'Count','FontSize',13);
title(ax4,'Game Length Distribution by Player Count','FontSize',14,'FontWeight','bold');
legend(ax4,'Location','northeast','FontSize',11);

print(fig4, fullfile(outputDir,['PRESENTATION_' timestamp '_plot4_game_length.png']), '-dpng','-r150');
close(fig4);
fprintf('Plot 4 saved.\n');

%% =========================================================================
%% Console summary
%% =========================================================================

fprintf('\n=== DATA SUMMARY ===\n');
fprintf('2-player matchups:\n');

matchupInfo = {
    'random',      'heuristic',   'random vs heuristic',      'heuristic';
    'heuristic',   'monte_carlo', 'heuristic vs monte_carlo', 'heuristic';
    'heuristic',   'mcts',        'heuristic vs mcts',        'heuristic';
    'monte_carlo', 'mcts',        'monte_carlo vs mcts',      'mcts'};

for m = 1:size(matchupInfo,1)
    a1  = matchupInfo{m,1}; a2  = matchupInfo{m,2};
    lbl = matchupInfo{m,3}; sw  = matchupInfo{m,4};
    mask = cellfun(@(r) ...
        (strcmp(r.p1_agent,a1) && strcmp(r.p2_agent,a2)) || ...
        (strcmp(r.p1_agent,a2) && strcmp(r.p2_agent,a1)), rows2);
    ng   = sum(mask);
    nwin = sum(cellfun(@(r) strcmp(r.winner_agent,sw), rows2(mask)));
    fprintf('  %-32s %3d games, %3d %s wins\n', [lbl ':'], ng, nwin, sw);
end

fprintf('\n4-player (%d games):\n', n4);
for i = 1:nA
    fprintf('  %-20s %3d (%.0f%%)\n', [agents{i} ' wins:'], wins4(i), wr4(i)*100);
end
fprintf('\nMean game length 2p: %.0f turns\n', mean2);
fprintf('Mean game length 4p: %.0f turns\n', mean4);

end

%% --- Local helper ---
function idx = aIdx(agents, name)
f = find(strcmp(agents, name), 1);
if isempty(f), idx = 0; else, idx = f; end
end
