%% ============================================================
%  ROTATION SPEED (ALL ROTATION EVENTS)
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
    if isnumeric(filterTrial) && ~ismember(a.TrialNum, filterTrial), mask(i) = false; end
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
    metrics(i).TargetDeg = tr.TargetDeg;

    % --- 1. ENCODING ROTATION METRICS ---
    metrics(i).Enc_PeakSpeedHead  = compute_peak_yaw_speed(tr.Traces.EncodingRotateHeadTrace);
    metrics(i).Enc_PeakSpeedTorso = compute_peak_yaw_speed(tr.Traces.EncodingRotateTorsoTrace);
    metrics(i).Enc_MeanSpeedHead  = compute_mean_yaw_speed(tr.Traces.EncodingRotateHeadTrace);
    metrics(i).Enc_MeanSpeedTorso = compute_mean_yaw_speed(tr.Traces.EncodingRotateTorsoTrace);

    % --- 2. RESPONSE ROTATION METRICS ---
    metrics(i).Res_PeakSpeedHead  = compute_peak_yaw_speed(tr.Traces.ResponseRotationHeadTrace);
    metrics(i).Res_PeakSpeedTorso = compute_peak_yaw_speed(tr.Traces.ResponseRotationTorsoTrace);
    metrics(i).Res_MeanSpeedHead  = compute_mean_yaw_speed(tr.Traces.ResponseRotationHeadTrace);
    metrics(i).Res_MeanSpeedTorso = compute_mean_yaw_speed(tr.Traces.ResponseRotationTorsoTrace);
end

%% --- STEP 3: OUTPUT ----------------------------------------
fprintf('\n================ ROTATION SPEED RESULTS ================\n');
fprintf('N = %d trials\n', N);

% --- Print Encoding Results ---
fprintf('\n--- ENCODING ROTATION -----------------------------------------------------\n');
fprintf('%-44s  %6s  %6s  %6s  %6s  %6s\n', 'Metric', 'N', 'Mean', 'SD', 'Min', 'Max');
print_row('Enc Peak Speed — Head  (deg/s)',  [metrics.Enc_PeakSpeedHead]);
print_row('Enc Peak Speed — Torso (deg/s)',  [metrics.Enc_PeakSpeedTorso]);
print_row('Enc Mean Speed — Head  (deg/s)',  [metrics.Enc_MeanSpeedHead]);
print_row('Enc Mean Speed — Torso (deg/s)',  [metrics.Enc_MeanSpeedTorso]);

% --- Print Response Results ---
fprintf('\n--- RESPONSE ROTATION -----------------------------------------------------\n');
fprintf('%-44s  %6s  %6s  %6s  %6s  %6s\n', 'Metric', 'N', 'Mean', 'SD', 'Min', 'Max');
print_row('Res Peak Speed — Head  (deg/s)',  [metrics.Res_PeakSpeedHead]);
print_row('Res Peak Speed — Torso (deg/s)',  [metrics.Res_PeakSpeedTorso]);
print_row('Res Mean Speed — Head  (deg/s)',  [metrics.Res_MeanSpeedHead]);
print_row('Res Mean Speed — Torso (deg/s)',  [metrics.Res_MeanSpeedTorso]);
fprintf('---------------------------------------------------------------------------\n');

% Save final combined table
assignin('base', 'RotationSpeedTable', struct2table(metrics));

%% --- LOCAL FUNCTIONS ---------------------------------------
function val = resolve_filter(code, map)
    if strcmp(code, 'All'), val = NaN; else, val = map(code); end
end

function spd = compute_peak_yaw_speed(trace)
    if isempty(trace) || ~isfield(trace, 'yaw') || ~isfield(trace, 'time') || numel(trace.yaw) < 2
        spd = NaN; return;
    end
    dt = diff(trace.time(:));
    dy = diff(trace.yaw(:));
    dt(dt <= 0) = NaN;
    spd = max(abs(dy ./ dt), [], 'omitnan');
end

function spd = compute_mean_yaw_speed(trace)
    if isempty(trace) || ~isfield(trace, 'yaw') || ~isfield(trace, 'time') || numel(trace.yaw) < 2
        spd = NaN; return;
    end
    
    % 1. Calculate total degrees rotated safely handling zig-zags
    dy = diff(trace.yaw(:));
    total_rotation = sum(abs(dy)); 
    
    % 2. Calculate total time securely avoiding cumulative float errors
    dur = trace.time(end) - trace.time(1);
    
    % 3. Calculate true average speed
    if dur <= 0, spd = NaN; return; end
    spd = total_rotation / dur;
end

function print_row(label, vals)
    vals = vals(~isnan(vals));
    if isempty(vals), fprintf('%-44s  %6d  %6s  %6s  %6s  %6s\n', label, 0, '—', '—', '—', '—');
    else, fprintf('%-44s  %6d  %6.3f  %6.3f  %6.3f  %6.3f\n', label, numel(vals), mean(vals), std(vals), min(vals), max(vals)); end
end
