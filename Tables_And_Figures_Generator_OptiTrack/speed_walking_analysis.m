%% ============================================================
%  WALKING SPEED
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
metrics = struct('TrialNum', {}, 'TargetDist', {}, 'Walk_PeakSpeedHead', {}, 'Walk_PeakSpeedTorso', {}, ...
                 'Walk_MeanSpeedHead', {}, 'Walk_MeanSpeedTorso', {});
for i = 1:N
    tr = subset(i);
    metrics(i).TrialNum   = tr.TrialNum;
    metrics(i).TargetDist = tr.TargetDist;

    % Dynamic field referencing to compute both Peak and Mean
    metrics(i).Walk_PeakSpeedHead  = compute_peak_walk_speed(tr.Traces.PhysicallyWalkHeadTrace);
    metrics(i).Walk_PeakSpeedTorso = compute_peak_walk_speed(tr.Traces.PhysicallyWalkTorsoTrace);
    metrics(i).Walk_MeanSpeedHead  = compute_mean_walk_speed(tr.Traces.PhysicallyWalkHeadTrace);
    metrics(i).Walk_MeanSpeedTorso = compute_mean_walk_speed(tr.Traces.PhysicallyWalkTorsoTrace);
end

%% --- STEP 3: OUTPUT ----------------------------------------
fprintf('\n================ WALKING SPEED RESULTS ================\n');
fprintf('N = %d trials\n---------------------------------------------------------------------------\n', N);
fprintf('%-44s  %6s  %6s  %6s  %6s  %6s\n', 'Metric', 'N', 'Mean', 'SD', 'Min', 'Max');
print_row('Peak Walk Speed — Head  (m/s)',  [metrics.Walk_PeakSpeedHead]);
print_row('Peak Walk Speed — Torso (m/s)',  [metrics.Walk_PeakSpeedTorso]);
print_row('Mean Walk Speed — Head  (m/s)',  [metrics.Walk_MeanSpeedHead]);
print_row('Mean Walk Speed — Torso (m/s)',  [metrics.Walk_MeanSpeedTorso]);

assignin('base', 'WalkSpeedTable', struct2table(metrics));

%% --- STEP 4: SPEED OVER TIME VISUALIZATION ----------
head_traces = {};
torso_traces = {};

for i = 1:N
    tr = subset(i);
    if ~isempty(tr.Traces.PhysicallyWalkHeadTrace) && isfield(tr.Traces.PhysicallyWalkHeadTrace, 'x')
        head_traces{end+1} = tr.Traces.PhysicallyWalkHeadTrace;
    end
    if ~isempty(tr.Traces.PhysicallyWalkTorsoTrace) && isfield(tr.Traces.PhysicallyWalkTorsoTrace, 'x')
        torso_traces{end+1} = tr.Traces.PhysicallyWalkTorsoTrace;
    end
end

fprintf('Traces found: %d head, %d torso\n', numel(head_traces), numel(torso_traces));

if numel(head_traces) > 0 || numel(torso_traces) > 0
    figure('Name', 'Walking Speed Over Time', 'NumberTitle', 'off', 'Position', [100 100 1400 600]);
    set(gcf, 'PaperPositionMode', 'auto');
    
    % --- Head Walking Speed ---
    subplot(1, 2, 1);
    plot_walking_speed(head_traces, 'Head Walking Speed');
    ylabel('Speed (m/s)', 'FontSize', 11);
    xlabel('Time (s)', 'FontSize', 11);
    grid on;
    
    % --- Torso Walking Speed ---
    subplot(1, 2, 2);
    plot_walking_speed(torso_traces, 'Torso Walking Speed');
    ylabel('Speed (m/s)', 'FontSize', 11);
    xlabel('Time (s)', 'FontSize', 11);
    grid on;
    
    sgtitle('Walking Speed Over Time (All Trials)', 'FontSize', 13, 'FontWeight', 'bold');
else
    fprintf('No walking traces found. Check if PhysicallyWalkHeadTrace/TorsoTrace exist in data.\n');
end

%% --- LOCAL FUNCTIONS ---------------------------------------
function val = resolve_filter(code, map)
    if strcmp(code, 'All'), val = NaN; else, val = map(code); end
end

function spd = compute_peak_walk_speed(trace)
    if isempty(trace) || ~isfield(trace, 'x') || ~isfield(trace, 'z') ...
            || ~isfield(trace, 'time') || numel(trace.x) < 2
        spd = NaN; return;
    end
    dx = diff(trace.x(:));
    dz = diff(trace.z(:));
    dt = diff(trace.time(:));
    dt(dt <= 0) = NaN; % Handle hardware hiccups cleanly
    
    inst_dist = sqrt(dx.^2 + dz.^2); % Frame-by-frame hypotenuse spatial step
    spd = max(inst_dist ./ dt, [], 'omitnan'); % Find highest instantaneous speed
end

function spd = compute_mean_walk_speed(trace)
    if isempty(trace) || ~isfield(trace, 'x') || ~isfield(trace, 'z') ...
            || ~isfield(trace, 'time') || numel(trace.x) < 2
        spd = NaN; return;
    end
    dx  = diff(trace.x(:));
    dz  = diff(trace.z(:));
    dist = sum(sqrt(dx.^2 + dz.^2)); % True continuous path distance length
    
    % One-step efficient shortcut for time duration (avoids float accumulation errors)
    dur  = trace.time(end) - trace.time(1); 
    
    if dur <= 0, spd = NaN; return; end
    spd = dist / dur;
end

function print_row(label, vals)
    vals = vals(~isnan(vals));
    if isempty(vals), fprintf('%-44s  %6d  %6s  %6s  %6s  %6s\n', label, 0, '—', '—', '—', '—');
    else, fprintf('%-44s  %6d  %6.3f  %6.3f  %6.3f  %6.3f\n', label, numel(vals), mean(vals), std(vals), min(vals), max(vals)); end
end

function plot_walking_speed(traces, title_str)
    if isempty(traces)
        text(0.5, 0.5, 'No data available', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
        title(title_str, 'FontSize', 11);
        return;
    end
    
    hold on;
    colors = lines(numel(traces));
    
    for i = 1:numel(traces)
        trace = traces{i};
        if isempty(trace) || ~isfield(trace, 'x') || ~isfield(trace, 'z') || ~isfield(trace, 'time') || numel(trace.x) < 2
            continue;
        end
        
        time = trace.time(:);
        x = trace.x(:);
        z = trace.z(:);
        
        % Convert time to seconds if in milliseconds
        if max(time) > 100
            time = time / 1000;
        end
        
        % Compute speed as distance per unit time
        dx = diff(x);
        dz = diff(z);
        dt = diff(time);
        dt(dt <= 0) = NaN;
        
        inst_dist = sqrt(dx.^2 + dz.^2);
        speed = inst_dist ./ dt;
        time_speed = time(1:end-1);
        
        plot(time_speed, speed, 'Color', colors(i, :), 'LineWidth', 1.5, 'DisplayName', sprintf('Trial %d', i), 'Marker', 'none');
    end
    
    hold off;
    title(title_str, 'FontSize', 11);
    
    % Set axis limits
    ax = gca;
    ax.XLim = [0 max(ax.XLim)];
    
    if numel(traces) > 1
        legend('Location', 'best', 'FontSize', 9);
    end
end
