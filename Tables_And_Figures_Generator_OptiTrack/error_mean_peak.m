%% ============================================================
%  ANALYSIS 4: RIGID BODY SOLVER ERROR
%% ============================================================

%% --- FILTERS (set to 'All' to include everything) ----------
filterTrial    = 1 : 64;   % Enter a specific number (e.g., 15) or range (e.g., 15:20)
filterDir      = 'All';   % 'L'    | 'R'    | 'All'
filterQuadrant = 'All';   % 'Q1'   | 'Q2'   | 'Q3'   | 'Q4'   | 'All'
filterDist     = 'All';   % 'D1'   | 'D2'   | 'D3'   | 'D4'   | 'All'
filterType     = 'All';   % 'I'    | 'P'    | 'All'
filterPos      = 'All';   % 'LPos' | 'RPos' | 'All'

%% --- LOOKUP TABLES -----------------------------------------
quadrantMap = containers.Map({'Q1','Q2','Q3','Q4'}, [60, 120, 240, 300]);
distanceMap = containers.Map({'D1','D2','D3','D4'}, [1.0, 1.5, 2.0, 2.5]);

%% --- STEP 1: FILTERING -------------------------------------
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
    if ~isnan(targetDegFilter)  && a.TargetDeg  ~= targetDegFilter,   mask(i) = false; end
    if ~isnan(targetDistFilter) && a.TargetDist ~= targetDistFilter,  mask(i) = false; end
end

subset = accepted(mask);
N = numel(subset);
if N == 0, error('No trials match the selected filters.'); end

%% --- STEP 2: METRIC COMPUTATION ----------------------------
metrics(N) = struct();
for i = 1:N
    tr = subset(i);
    metrics(i).TrialNum  = tr.TrialNum;
    metrics(i).TaskType  = tr.TaskType;

    % --- 1. PHYSICALLY WALK ERRORS ---
    metrics(i).Walk_PeakErrHead  = compute_peak_error(tr.Traces.PhysicallyWalkHeadTrace);
    metrics(i).Walk_PeakErrTorso = compute_peak_error(tr.Traces.PhysicallyWalkTorsoTrace);
    metrics(i).Walk_MeanErrHead  = compute_mean_error(tr.Traces.PhysicallyWalkHeadTrace);
    metrics(i).Walk_MeanErrTorso = compute_mean_error(tr.Traces.PhysicallyWalkTorsoTrace);
    
    
    % --- 2. ENCODING ROTATION ERRORS ---
    metrics(i).Enc_PeakErrHead  = compute_peak_error(tr.Traces.EncodingRotateHeadTrace);
    metrics(i).Enc_PeakErrTorso = compute_peak_error(tr.Traces.EncodingRotateTorsoTrace);
    metrics(i).Enc_MeanErrHead  = compute_mean_error(tr.Traces.EncodingRotateHeadTrace);
    metrics(i).Enc_MeanErrTorso = compute_mean_error(tr.Traces.EncodingRotateTorsoTrace);


    % --- 3. RESPONSE ROTATION ERRORS ---
    metrics(i).Res_PeakErrHead  = compute_peak_error(tr.Traces.ResponseRotationHeadTrace);
    metrics(i).Res_PeakErrTorso = compute_peak_error(tr.Traces.ResponseRotationTorsoTrace);
    metrics(i).Res_MeanErrHead  = compute_mean_error(tr.Traces.ResponseRotationHeadTrace);
    metrics(i).Res_MeanErrTorso  = compute_mean_error(tr.Traces.ResponseRotationTorsoTrace);
end

%% --- STEP 3: OUTPUT ----------------------------------------
fprintf('\n================ RIGID BODY ERROR RESULTS ================\n');
fprintf('N = %d trials\n', N);

% --- Print Walking Phase ---
fprintf('\n--- PHYSICALLY WALK PHASE -------------------------------------------------\n');
fprintf('%-44s  %6s  %6s  %6s  %6s  %6s\n', 'Metric', 'N', 'Mean', 'SD', 'Min', 'Max');
print_row('Walk Peak Error — Head  (mm)', [metrics.Walk_PeakErrHead]  * 1000);
print_row('Walk Peak Error — Torso (mm)', [metrics.Walk_PeakErrTorso] * 1000);
print_row('Walk Mean Error — Head  (mm)', [metrics.Walk_MeanErrHead]  * 1000);
print_row('Walk Mean Error — Torso (mm)', [metrics.Walk_MeanErrTorso] * 1000);

% --- Print Encoding Phase ---
fprintf('\n--- ENCODING ROTATION PHASE -----------------------------------------------\n');
fprintf('%-44s  %6s  %6s  %6s  %6s  %6s\n', 'Metric', 'N', 'Mean', 'SD', 'Min', 'Max');
print_row('Enc Peak Error — Head  (mm)',  [metrics.Enc_PeakErrHead]  * 1000); % convert to mm for scannability
print_row('Enc Peak Error — Torso (mm)',  [metrics.Enc_PeakErrTorso] * 1000);
print_row('Enc Mean Error — Head  (mm)',  [metrics.Enc_MeanErrHead]  * 1000);
print_row('Enc Mean Error — Torso (mm)',  [metrics.Enc_MeanErrTorso] * 1000);


% --- Print Response Phase ---
fprintf('\n--- RESPONSE ROTATION PHASE -----------------------------------------------\n');
fprintf('%-44s  %6s  %6s  %6s  %6s  %6s\n', 'Metric', 'N', 'Mean', 'SD', 'Min', 'Max');
print_row('Res Peak Error — Head  (mm)',  [metrics.Res_PeakErrHead]  * 1000);
print_row('Res Peak Error — Torso (mm)',  [metrics.Res_PeakErrTorso] * 1000);
print_row('Res Mean Error — Head  (mm)',  [metrics.Res_MeanErrHead]  * 1000);
print_row('Res Mean Error — Torso (mm)',  [metrics.Res_MeanErrTorso] * 1000);
fprintf('---------------------------------------------------------------------------\n');

% Save final combined table to workspace
assignin('base', 'TrackingErrorTable', struct2table(metrics));

%% --- LOCAL FUNCTIONS ---------------------------------------
function val = resolve_filter(code, map)
    if strcmp(code, 'All'), val = NaN; else, val = map(code); end
end

function errVal = compute_peak_error(trace)
    if isempty(trace) || ~isfield(trace, 'error') || isempty(trace.error)
        errVal = NaN; return;
    end
    % Capture max tracking residual found within this trace's timeline
    errVal = max(trace.error(:), [], 'omitnan');
end

function errVal = compute_mean_error(trace)
    if isempty(trace) || ~isfield(trace, 'error') || ~isfield(trace, 'time') || numel(trace.error) < 2
        errVal = NaN; return;
    end
    
    dt = diff(trace.time(:));
    dt(dt <= 0) = NaN;
    
    % Weight the solver error by time step duration to stay robust against frame drops
    totalTime = sum(dt, 'omitnan');
    if totalTime <= 0, errVal = NaN; return; end
    
    % Mean calculation using time-slice integration shortcut
    errVal = sum(trace.error(1:end-1) .* dt, 'omitnan') / totalTime;
end

function print_row(label, vals)
    vals = vals(~isnan(vals));
    if isempty(vals), fprintf('%-44s  %6d  %6s  %6s  %6s  %6s\n', label, 0, '—', '—', '—', '—');
    else, fprintf('%-44s  %6d  %6.3f  %6.3f  %6.3f  %6.3f\n', label, numel(vals), mean(vals), std(vals), min(vals), max(vals)); end
end
