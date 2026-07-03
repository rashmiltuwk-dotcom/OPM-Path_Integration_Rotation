%% ============================================================
%  PATH VISUALIZER WITH METADATA FILTERING (MULTI-PARTICIPANT)
% ============================================================

%% --- USER PARAMETERS & FILTERS -----------------------------
filterTrial    = 1:64;  
filterDir      = 'All'; 
filterQuadrant = 'All'; 
filterDist     = 'All'; 
filterType     = 'All'; 
filterPos      = 'All'; 

headTraces = {
    'OpenEyesHeadTrace', 'CloseEyesHeadTrace', 'PhysicallyWalkHeadTrace', ...
    'StationaryHeadTraceOne', 'EncodingRotateHeadTrace', 'StationaryHeadTraceTwo', ...
    'ResponseRotationHeadTrace', 'ImagineWalkingHeadTrace', 'StationaryHeadTraceThree'
};

%% --- 1. LOAD & MERGE MASTERDATA FROM PARTICIPANT FOLDERS ----
folderPath = 'C:\Users\spaceandmem\rashmil_opm\grouped_data';

participantFolders = dir(fullfile(folderPath, 'p*'));
participantFolders = participantFolders([participantFolders.isdir]);

MasterData = [];
fprintf('Loading participant folders...\n');
for p = 1:length(participantFolders)
    participantID = lower(participantFolders(p).name);
    participantPath = fullfile(participantFolders(p).folder, participantFolders(p).name);
    blockFiles = dir(fullfile(participantPath, '*MasterData.mat'));
    
    if isempty(blockFiles)
        continue;
    end
    
    fprintf('  %s: %d block(s)\n', participantID, length(blockFiles));
    for b = 1:length(blockFiles)
        fullFileName = fullfile(blockFiles(b).folder, blockFiles(b).name);
        data = load(fullFileName);
        
        if ~isfield(data, 'MasterData')
            continue;
        end
        currentData = data.MasterData;
        if isempty(currentData)
            fprintf('    %s SKIPPED (empty)\n', blockFiles(b).name);
            continue;
        end
        
        [currentData.Participant] = deal(participantID);
        
        if isempty(MasterData)
            MasterData = currentData;
        else
            fields_old = fieldnames(MasterData(1));
            fields_new = fieldnames(currentData(1));
            missing_in_new = setdiff(fields_old, fields_new);
            missing_in_old = setdiff(fields_new, fields_old);
            
            if ~isempty(missing_in_new)
                for k = 1:length(currentData)
                    for f = 1:length(missing_in_new)
                        currentData(k).(missing_in_new{f}) = [];
                    end
                end
            end
            
            if ~isempty(missing_in_old)
                for k = 1:length(MasterData)
                    for f = 1:length(missing_in_old)
                        MasterData(k).(missing_in_old{f}) = [];
                    end
                end
            end
            
            MasterData = [MasterData, currentData];
        end
        fprintf('    %s (%d trials)\n', blockFiles(b).name, numel(currentData));
    end
end

%% --- 2. FILTER DATA ----------------------------------------
quadrantMap = containers.Map({'Q1','Q2','Q3','Q4'}, [60, 120, 240, 300]);
distanceMap = containers.Map({'D1','D2','D3','D4'}, [1.0, 1.5, 2.0, 2.5]);

accepted = MasterData(strcmp({MasterData.Status}, 'Accepted'));
targetDegFilter  = resolve_filter(filterQuadrant, quadrantMap);
targetDistFilter = resolve_filter(filterDist,     distanceMap);

mask = true(1, numel(accepted));
for i = 1:numel(accepted)
    a = accepted(i);
    if isnumeric(filterTrial)   && ~ismember(a.TrialNum, filterTrial), mask(i) = false; end
    if ~strcmp(filterDir,  'All') && ~strcmp(a.Direction, filterDir),  mask(i) = false; end
    if ~strcmp(filterType, 'All') && ~strcmp(a.TaskType,  filterType), mask(i) = false; end
    if ~strcmp(filterPos,  'All') && ~strcmp(a.Position,  filterPos),  mask(i) = false; end
    if ~isnan(targetDegFilter)  && a.TargetDeg  ~= targetDegFilter,    mask(i) = false; end
    if ~isnan(targetDistFilter) && a.TargetDist ~= targetDistFilter,   mask(i) = false; end
end

subset = accepted(mask);
if isempty(subset), error('No trials match filters.'); end
participants = unique({subset.Participant});
nParticipants = numel(participants);

fprintf('\nFiltering: %d trials, %d participants\n', numel(subset), nParticipants);

%% --- 3. SETUP FIGURE ----------------------------------------
fig = figure(1);
clf;
set(fig, 'Visible', 'on');
set(fig, 'Position', [100, 100, 900, 800], 'Color', 'w');
set(fig, 'Renderer', 'painters');
hold on;
drawnow;

participantColors = lines(nParticipants);
plot(0, 0, 'k*', 'MarkerSize', 15, 'LineWidth', 2);

%% --- 4. PLOT TRACES ----------------------------------------
headCount = 0;
allX = [];
allZ = [];

for pIdx = 1:nParticipants
    pid = participants{pIdx};
    color = participantColors(pIdx, :);
    pData = subset(strcmp({subset.Participant}, pid));
    validTrials = unique([pData.TrialNum]);
    pHeadCount = 0;

    for t = validTrials
        trialRuns = pData([pData.TrialNum] == t);
        entry = trialRuns(end);
        
        for i = 1:length(headTraces)
            tr = get_trace_data(entry, headTraces{i});
            if ~isempty(tr) && isnumeric(tr.x) && isnumeric(tr.z) && ~isempty(tr.x) && ~isempty(tr.z)
                allX = [allX; tr.x(:)];
                allZ = [allZ; tr.z(:)];
                plot(tr.x, tr.z, 'Color', color, 'LineWidth', 2.5);
                headCount = headCount + 1;
                pHeadCount = pHeadCount + 1;
            end
        end
    end
    fprintf('  %s: %d traces\n', pid, pHeadCount);
end

fprintf('Total: %d traces plotted\n', headCount);

% Set axis limits to actual data range
if ~isempty(allX) && ~isempty(allZ)
    xpad = 0.001;
    zpad = 0.001;
    xlim([min(allX) - xpad, max(allX) + xpad]);
    ylim([min(allZ) - zpad, max(allZ) + zpad]);
end

%% --- 5. FORMAT PLOT ----------------------------------------
title(sprintf('Filtered Path: XZ Coordinates (N = %d Trials, %d Participants)', ...
    numel(unique([subset.TrialNum])), nParticipants), 'FontSize', 16);
xlabel('Room X Position (Meters)', 'FontSize', 14);
ylabel('Room Z Position (Meters)', 'FontSize', 14);

pHandles = gobjects(1, nParticipants);
for i = 1:nParticipants
    pHandles(i) = plot(nan, nan, 'Color', participantColors(i, :), 'LineWidth', 3);
end
legend([pHandles, plot(nan, nan, 'k*', 'MarkerSize', 15)], [participants, {'Target Center'}], ...
    'Location', 'bestoutside');

set(gca, 'XDir', 'reverse');
grid on;
hold off;

fprintf('Figure should now be visible. Press Ctrl+C to exit.\n');

% Force display
drawnow expose;

% Bring figure to foreground
figure(fig);
shg;

fprintf('Figure complete..\n');

%% --- LOCAL FUNCTIONS ----------------------------------------
function val = resolve_filter(code, map)
    if strcmp(code, 'All'), val = NaN; else, val = map(code); end
end

function tr = get_trace_data(entry, traceName)
    tr = [];
    if isfield(entry.Traces, traceName) && ~isempty(entry.Traces.(traceName))
        tr = entry.Traces.(traceName);
        if ~(isfield(tr, 'x') && isfield(tr, 'z')), tr = []; end
    end
end
