%% ============================================================
%  PATH VISUALIZER WITH METADATA FILTERING
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

torsoTraces = {
    'OpenEyesTorsoTrace', 'CloseEyesTorsoTrace', 'PhysicallyWalkTorsoTrace', ...
    'StationaryTorsoTraceOne', 'EncodingRotateTorsoTrace', 'StationaryTorsoTraceTwo', ...
    'ResponseRotationTorsoTrace', 'ImagineWalkingTorsoTrace', 'StationaryTorsoTraceThree'
};

%% --- 1. FILTERING & PRE-PROCESSING -------------------------
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
validTrials = unique([subset.TrialNum]);

%% --- 2. SETUP FIGURE & LEGEND ------------------------------
figure(1); clf; hold on;
set(gcf, 'Position', [100, 100, 900, 800], 'Color', 'w');

pHead   = plot(nan, nan, 'Color', [0.85 0.33 0.10], 'LineWidth', 2);
pTorso  = plot(nan, nan, 'Color', [0.00 0.45 0.74], 'LineWidth', 2);
pTarget = plot(-0.25, 0, 'k*', 'MarkerSize', 10, 'LineWidth', 1.5);

%% --- 3. LOOP & PLOT (ONLY FILTERED DATA) -------------------
for t = validTrials
    trialRuns = subset([subset.TrialNum] == t);
    entry = trialRuns(end); 
    
    for i = 1:length(headTraces)
        tr = get_trace_data(entry, headTraces{i});
        if ~isempty(tr)
            p = plot(tr.z, tr.x, 'Color', [0.85 0.33 0.10]);
            p.Color(4) = 0.3;
        end
    end
    
    for i = 1:length(torsoTraces)
        tr = get_trace_data(entry, torsoTraces{i});
        if ~isempty(tr)
            p = plot(tr.z, tr.x, 'Color', [0.00 0.45 0.74]);
            p.Color(4) = 0.3;
        end
    end
end

%% --- 4. FORMATTING -----------------------------------------
title(sprintf('Filtered Path: ZX Coordinates (N = %d Trials)', length(validTrials)), 'FontSize', 16);
xlabel('Room Z Position (Meters)', 'FontSize', 14);
ylabel('Room X Position (Meters)', 'FontSize', 14);
legend([pHead, pTorso, pTarget], {'Head Path', 'Torso Path', 'Target Center'}, 'Location', 'bestoutside');
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
