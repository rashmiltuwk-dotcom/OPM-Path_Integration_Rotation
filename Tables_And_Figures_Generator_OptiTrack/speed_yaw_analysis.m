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
metrics = struct('TrialNum', {}, 'TargetDeg', {}, 'Enc_PeakSpeedHead', {}, 'Enc_PeakSpeedTorso', {}, ...
                 'Enc_MeanSpeedHead', {}, 'Enc_MeanSpeedTorso', {}, 'Res_PeakSpeedHead', {}, ...
                 'Res_PeakSpeedTorso', {}, 'Res_MeanSpeedHead', {}, 'Res_MeanSpeedTorso', {});
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

fprintf('\n--- ENCODING ROTATION -----------------------------------------------------\n');
fprintf('%-44s  %6s  %6s  %6s  %6s  %6s\n', 'Metric', 'N', 'Mean', 'SD', 'Min', 'Max');
print_row('Enc Peak Speed — Head  (deg/s)',  [metrics.Enc_PeakSpeedHead]);
print_row('Enc Peak Speed — Torso (deg/s)',  [metrics.Enc_PeakSpeedTorso]);
print_row('Enc Mean Speed — Head  (deg/s)',  [metrics.Enc_MeanSpeedHead]);
print_row('Enc Mean Speed — Torso (deg/s)',  [metrics.Enc_MeanSpeedTorso]);

fprintf('\n--- RESPONSE ROTATION -----------------------------------------------------\n');
fprintf('%-44s  %6s  %6s  %6s  %6s  %6s\n', 'Metric', 'N', 'Mean', 'SD', 'Min', 'Max');
print_row('Res Peak Speed — Head  (deg/s)',  [metrics.Res_PeakSpeedHead]);
print_row('Res Peak Speed — Torso (deg/s)',  [metrics.Res_PeakSpeedTorso]);
print_row('Res Mean Speed — Head  (deg/s)',  [metrics.Res_MeanSpeedHead]);
print_row('Res Mean Speed — Torso (deg/s)',  [metrics.Res_MeanSpeedTorso]);
fprintf('---------------------------------------------------------------------------\n');

assignin('base', 'RotationSpeedTable', struct2table(metrics));

%% --- STEP 4: VELOCITY OVER TIME VISUALIZATION ----------
figure('Name', 'Rotation Velocity Over Time', 'NumberTitle', 'off', 'Position', [100 100 1400 900]);
set(gcf, 'PaperPositionMode', 'auto');

enc_head_traces  = {};
enc_torso_traces = {};
res_head_traces  = {};
res_torso_traces = {};

for i = 1:N
    tr = subset(i);
    if ~isempty(tr.Traces.EncodingRotateHeadTrace)    && isfield(tr.Traces.EncodingRotateHeadTrace,    'yaw'), enc_head_traces{end+1}  = tr.Traces.EncodingRotateHeadTrace;    end
    if ~isempty(tr.Traces.EncodingRotateTorsoTrace)   && isfield(tr.Traces.EncodingRotateTorsoTrace,   'yaw'), enc_torso_traces{end+1} = tr.Traces.EncodingRotateTorsoTrace;   end
    if ~isempty(tr.Traces.ResponseRotationHeadTrace)  && isfield(tr.Traces.ResponseRotationHeadTrace,  'yaw'), res_head_traces{end+1}  = tr.Traces.ResponseRotationHeadTrace;  end
    if ~isempty(tr.Traces.ResponseRotationTorsoTrace) && isfield(tr.Traces.ResponseRotationTorsoTrace, 'yaw'), res_torso_traces{end+1} = tr.Traces.ResponseRotationTorsoTrace; end
end

subplot(2,2,1); plot_velocity_traces(enc_head_traces,  'Encoding — Head Rotation Velocity');   ylabel('Velocity (deg/s)', 'FontSize', 11); grid on;
subplot(2,2,2); plot_velocity_traces(enc_torso_traces, 'Encoding — Torso Rotation Velocity');  ylabel('Velocity (deg/s)', 'FontSize', 11); grid on;
subplot(2,2,3); plot_velocity_traces(res_head_traces,  'Response — Head Rotation Velocity');   xlabel('Time (s)', 'FontSize', 11); ylabel('Velocity (deg/s)', 'FontSize', 11); grid on;
subplot(2,2,4); plot_velocity_traces(res_torso_traces, 'Response — Torso Rotation Velocity');  xlabel('Time (s)', 'FontSize', 11); ylabel('Velocity (deg/s)', 'FontSize', 11); grid on;

sgtitle('Rotation Velocity Over Time (All Trials)', 'FontSize', 13, 'FontWeight', 'bold');
pause(0.1);

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
    raw = abs(dy ./ dt);
    % Clamp to physiologically plausible range (humans cannot exceed ~400 deg/s)
    raw(raw > 400) = NaN;
    spd = max(raw, [], 'omitnan');
end

function spd = compute_mean_yaw_speed(trace)
    if isempty(trace) || ~isfield(trace, 'yaw') || ~isfield(trace, 'time') || numel(trace.yaw) < 2
        spd = NaN; return;
    end
    dy  = diff(trace.yaw(:));
    dur = trace.time(end) - trace.time(1);
    if dur <= 0, spd = NaN; return; end
    spd = sum(abs(dy)) / dur;
end

function print_row(label, vals)
    vals = vals(~isnan(vals));
    if isempty(vals), fprintf('%-44s  %6d  %6s  %6s  %6s  %6s\n', label, 0, '—', '—', '—', '—');
    else, fprintf('%-44s  %6d  %6.3f  %6.3f  %6.3f  %6.3f\n', label, numel(vals), mean(vals), std(vals), min(vals), max(vals)); end
end

function plot_velocity_traces(traces, title_str)
    if isempty(traces)
        text(0.5, 0.5, 'No data available', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
        title(title_str, 'FontSize', 11); return;
    end

    hold on;
    colors = lines(numel(traces));

    for i = 1:numel(traces)
        trace = traces{i};
        if isempty(trace) || ~isfield(trace, 'yaw') || ~isfield(trace, 'time') || numel(trace.yaw) < 2
            continue;
        end

        time = trace.time(:);
        yaw  = trace.yaw(:);
        time = time - time(1);  % normalise to start at 0

        dt = diff(time);
        dy = diff(yaw);

        velocity = dy ./ dt;
        % Clamp to physiologically plausible range (humans cannot exceed ~400 deg/s)
        velocity(abs(velocity) > 400) = NaN;

        time_vel = time(1:end-1);
        plot(time_vel, velocity, 'Color', colors(i,:), 'LineWidth', 1.5, ...
            'DisplayName', sprintf('Trial %d', i), 'Marker', 'none');
    end

    hold off;
    title(title_str, 'FontSize', 11);
    xlabel('Time (s)', 'FontSize', 10);

    ax = gca;
    ax.XLim  = [0 5];
    ax.XTick = 0:1:5;

    if numel(traces) > 1
    legend('Location', 'none', 'Position', [0.45 0.45 0.1 0.1], 'FontSize', 9);
    end
end
