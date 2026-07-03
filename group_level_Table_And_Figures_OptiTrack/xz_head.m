%% ============================================================
%  PATH VISUALIZER WITH METADATA FILTERING (MULTI-PARTICIPANT)
%  Expects: <folderPath>/pXXX/*_MasterData.mat
%  Each participant folder can contain multiple block files
%  (e.g. P001_1_..._MasterData.mat, P001_2_..._MasterData.mat);
%  these are combined under that participant's ID, then all
%  participants are merged and color-coded in the plot.
% ============================================================

%% --- USER PARAMETERS & FILTERS -----------------------------
% Filter variables (Set to 'All' to ignore a filter)
filterTrial    = 1:64;  
filterDir      = 'All'; 
filterQuadrant = 'All'; 
filterDist     = 'All'; 
filterType     = 'All'; 
filterPos      = 'All'; 

% Trace Selection
headTraces = {
    'OpenEyesHeadTrace', 'CloseEyesHeadTrace', 'PhysicallyWalkHeadTrace', ...
    'StationaryHeadTraceOne', 'EncodingRotateHeadTrace', 'StationaryHeadTraceTwo', ...
    'ResponseRotationHeadTrace', 'ImagineWalkingHeadTrace', 'StationaryHeadTraceThree'
};

%% --- 1. LOCATE & MERGE MASTERDATA FILES ---------------------
folderPath = 'C:\Users\spaceandmem\rashmil_opm\grouped_data';

participantFolders = dir(fullfile(folderPath, 'p*'));
participantFolders = participantFolders([participantFolders.isdir]);
if isempty(participantFolders)
    error('No participant subfolders (e.g. "p001") found in "%s".', folderPath);
end

MasterData = [];
fprintf('Found %d participant folder(s) in %s...\n', length(participantFolders), folderPath);
for p = 1:length(participantFolders)
    participantID = lower(participantFolders(p).name);
    participantPath = fullfile(participantFolders(p).folder, participantFolders(p).name);

    blockFiles = dir(fullfile(participantPath, '*MasterData.mat'));
    if isempty(blockFiles)
        error('No "*MasterData.mat" block files found in "%s".', participantPath);
    end

    fprintf('  %s: %d block(s)\n', participantID, length(blockFiles));
    for b = 1:length(blockFiles)
        fullFileName = fullfile(blockFiles(b).folder, blockFiles(b).name);

        data = load(fullFileName);
        if ~isfield(data, 'MasterData')
            error('File "%s" does not contain a MasterData variable.', blockFiles(b).name);
        end
        currentData = data.MasterData;
        if isempty(currentData)
            error('File "%s" contains an empty MasterData variable.', blockFiles(b).name);
        end

        [currentData.Participant] = deal(participantID);

        if isempty(MasterData)
            MasterData = currentData;
        else
            if ~isequal(sort(fieldnames(MasterData(1))), sort(fieldnames(currentData(1))))
                error('Field mismatch between "%s" and previously loaded files.', blockFiles(b).name);
            end
            MasterData = [MasterData, currentData];
        end
        fprintf('    %s (%d trials)\n', blockFiles(b).name, numel(currentData));
    end
end

%% --- 2. FILTERING & PRE-PROCESSING -------------------------
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
if isempty(subset), error('No trials match the selected filters.'); end
participants = unique({subset.Participant});
nParticipants = numel(participants);

%% --- 3. SETUP FIGURE & LEGEND ------------------------------
figure(1); clf; hold on;
set(gcf, 'Position', [100, 100, 900, 800], 'Color', 'w');

participantColors = lines(nParticipants);
pTarget = plot(0, 0, 'k*', 'MarkerSize', 15, 'LineWidth', 2);

%% --- 4. LOOP & PLOT (ONE COLOR PER PARTICIPANT) ------------
headCount = 0;
legendHandles = gobjects(1, nParticipants);

for pIdx = 1:nParticipants
    pid = participants{pIdx};
    color = participantColors(pIdx, :);
    pData = subset(strcmp({subset.Participant}, pid));
    validTrials = unique([pData.TrialNum]);

    for t = validTrials
        trialRuns = pData([pData.TrialNum] == t);
        entry = trialRuns(end);

        for i = 1:length(headTraces)
            tr = get_trace_data(entry, headTraces{i});
            if ~isempty(tr)
                plot(tr.x, tr.z, 'Color', color, 'LineWidth', 2.5);
                headCount = headCount + 1;
            end
        end
    end

    legendHandles(pIdx) = plot(nan, nan, 'Color', color, 'LineWidth', 3);
end

fprintf('Traces found: %d head (across %d participants)\n', headCount, nParticipants);

%% --- 5. FORMATTING -----------------------------------------
title(sprintf('Filtered Path: XZ Coordinates (N = %d Trials, %d Participants)', ...
    numel(unique([subset.TrialNum])), nParticipants), 'FontSize', 16);
xlabel('Room X Position (Meters)', 'FontSize', 14);
ylabel('Room Z Position (Meters)', 'FontSize', 14);
legend([legendHandles, pTarget], [participants, {'Target Center'}], 'Location', 'bestoutside');
set(gca, 'XDir', 'reverse');
axis equal; grid on; hold off;

%% --- LOCAL FUNCTIONS ---------------------------------------
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
