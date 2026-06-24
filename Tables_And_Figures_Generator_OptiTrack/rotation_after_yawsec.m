%% --- DATA EXTRACTION ---
fprintf('--- EXTRACTING RESPONSEROTATATION TRACES ---\n');

% Check if MasterData exists in the workspace
if ~exist('MasterData', 'var')
    error('MasterData not found. Please load your .mat file into the workspace first.');
end

accepted = MasterData(strcmp({MasterData.Status}, 'Accepted'));
N = numel(accepted);
if N == 0, error('No accepted trials in MasterData.'); end

results = table();
skipped_I_count = 0;
skipped_target_count = 0;

for i = 1:N
    tr = accepted(i);
    
    % --- TASK TYPE FILTER ---
    % Skip trials marked as 'I'
    if isfield(tr, 'TaskType') && strcmpi(strtrim(tr.TaskType), 'I')
        skipped_I_count = skipped_I_count + 1;
        continue; 
    end
    
    targetDeg = tr.TargetDeg; 
    
    % --- TARGET DEGREE FILTER ---
    % Only allow the specific targets requested
    valid_targets = [60, 120, 240, 300];
    if ~ismember(targetDeg, valid_targets)
        skipped_target_count = skipped_target_count + 1;
        continue;
    end
    
    if isfield(tr.Traces, 'ResponseRotationHeadTrace')
        head_trace = tr.Traces.ResponseRotationHeadTrace;
        if ~isempty(head_trace) && isfield(head_trace, 'yaw')
            head_results = analyzeTrace(head_trace, i, 'head', targetDeg);
            results = [results; head_results];
        end
    end
    
    if isfield(tr.Traces, 'ResponseRotationTorsoTrace')
        torso_trace = tr.Traces.ResponseRotationTorsoTrace;
        if ~isempty(torso_trace) && isfield(torso_trace, 'yaw')
            torso_results = analyzeTrace(torso_trace, i, 'torso', targetDeg);
            results = [results; torso_results];
        end
    end
end

if isempty(results)
    fprintf('\n***************************************************************\n');
    fprintf('WARNING: ZERO EVENTS FOUND.\n');
    fprintf('The velocity never dropped below your thresholds after the peak.\n');
    fprintf('***************************************************************\n\n');
    return;
end

fprintf('Filtered out %d TaskType ''I'' trials.\n', skipped_I_count);
fprintf('Filtered out %d trials with unanalyzed targets.\n', skipped_target_count);
fprintf('Processed %d remaining physical trials, extracted post-peak decelerations.\n\n', N - skipped_I_count - skipped_target_count);

%% --- SUMMARY STATISTICS ---
fprintf('%s\n', repmat('=', 1, 70));
fprintf('ROTATION ANALYSIS SUMMARY (Post-Peak Rotation)\n');
fprintf('%s\n\n', repmat('=', 1, 70));

% --- THRESHOLD RANGE: 0.5 to 7.5 deg/s in 0.5 increments ---
threshold_values = 0.5:0.5:7.5;
locations = {'head', 'torso'};

for loc_idx = 1:length(locations)
    location = locations{loc_idx};
    fprintf('%s ROTATION:\n', upper(location));
    fprintf('%s\n', repmat('-', 1, 70));
    
    for thr = threshold_values
        mask = strcmp(results.Location, location) & (results.Threshold == thr);
        filtered = results.TotalRotation(mask);
        
        if ~isempty(filtered)
            fprintf('\n  Threshold: %.1f deg/s\n', thr);
            fprintf('    Count: %d\n', length(filtered));
            fprintf('    Mean Rotation: %.4f°\n', mean(filtered));
            fprintf('    Rotation Range: [%.4f, %.4f]°\n', min(filtered), max(filtered));
        end
    end
    fprintf('\n');
end

%% --- PLOTS (Custom Boxplot for Total Rotation) ---
fprintf('Creating plots...\n');

figure('Name', 'Rotation Analysis', 'Color', 'w', 'Position', [100 100 1400 650]);

for loc_idx = 1:2
    subplot(1, 2, loc_idx);
    location = locations{loc_idx};
    hold on;
    
    plot_labels = {};
    x_positions = [];
    
    % --- DUMMY HANDLES FOR CLEAN LEGEND ---
    % We create invisible plots just so the legend has a clean reference
    h_green = plot(NaN, NaN, 'go', 'MarkerFaceColor', 'g', 'MarkerEdgeColor', 'k', 'MarkerSize', 8);
    h_yellow = plot(NaN, NaN, 'yo', 'MarkerFaceColor', 'y', 'MarkerEdgeColor', 'k', 'MarkerSize', 8);
    h_mean = plot(NaN, NaN, 'k-', 'LineWidth', 3);
    
    for thr_idx = 1:length(threshold_values)
        thr = threshold_values(thr_idx);
        mask = strcmp(results.Location, location) & (results.Threshold == thr);
        
        filtered = results.TotalRotation(mask);
        targets = results.TargetDeg(mask); 
        
        if ~isempty(filtered)
            x_positions = [x_positions, thr_idx];
            plot_labels{end+1} = sprintf('%.1f', thr);
            
            % Add random jitter to X so points don't completely overlap
            x_jitter = thr_idx + (rand(length(filtered), 1) - 0.5) * 0.3;
            
            % --- COLOR CODING LOGIC ---
            green_mask = (targets == 60) | (targets == 300);
            yellow_mask = (targets == 120) | (targets == 240);
            
            % Plot 60 and 300 TargetDeg (Green)
            if any(green_mask)
                scatter(x_jitter(green_mask), filtered(green_mask), 45, 'g', 'filled', 'MarkerEdgeColor', 'k', 'MarkerFaceAlpha', 0.7);
            end
            
            % Plot 120 and 240 TargetDeg (Yellow)
            if any(yellow_mask)
                scatter(x_jitter(yellow_mask), filtered(yellow_mask), 45, 'y', 'filled', 'MarkerEdgeColor', 'k', 'MarkerFaceAlpha', 0.7);
            end
            
            % Plot Mean as a thick black line
            mean_val = mean(filtered);
            plot([thr_idx-0.25, thr_idx+0.25], [mean_val, mean_val], 'k-', 'LineWidth', 3);
        end
    end
    
    if ~isempty(x_positions)
        set(gca, 'XTick', x_positions, 'XTickLabel', plot_labels, 'FontSize', 10);
    end
    
    proper_title_case = [upper(location(1)), location(2:end)];
    
    xlabel('Absolute Velocity Threshold (deg/s)', 'FontWeight', 'bold', 'FontSize', 11);
    ylabel('Absolute End of Epoch Rotation (degrees)', 'FontWeight', 'bold', 'FontSize', 11);
    title(sprintf('%s - Post-Peak Deceleration Rotation', proper_title_case), 'FontWeight', 'bold', 'FontSize', 12);
    
    grid on; grid minor;
    hold off;
end

% --- GLOBAL LEGEND ---
% Create a single legend attached to the figure, centered at the bottom
L = legend([h_green, h_yellow, h_mean], ...
    {'60° Rotation', '120° Rotation', 'Mean Rotation'}, ...
    'Orientation', 'horizontal', 'FontSize', 11);

% Center the legend explicitly
L.Units = 'normalized';
L.Position(1) = 0.5 - L.Position(3)/2; % Center X
L.Position(2) = 0.02; % Y position near bottom

sgtitle('Absolute Total Rotation From Threshold Crossing to End of Epoch', 'FontWeight', 'bold', 'FontSize', 14);
fprintf('Done!\n\n');

%% ========================================================================
function results = analyzeTrace(trace, trialIdx, location, targetDeg)
    
results = table();
original_time = trace.time(:);
yaw = trace.yaw(:);
total_len = length(original_time);

% Determine Start Index based on the target degrees, BUT cap it at 25% of the file length
if targetDeg == 60 || targetDeg == 300
    START_IDX = min(50, floor(total_len * 0.25));
elseif targetDeg == 120 || targetDeg == 240
    START_IDX = min(100, floor(total_len * 0.25));
else
    START_IDX = min(500, floor(total_len * 0.25)); % Default fallback
end

% Failsafe minimum start index
START_IDX = max(2, START_IDX);

time = original_time(START_IDX:end);
yaw = yaw(START_IDX:end);

dt = diff(time);
dyaw = diff(yaw);

valid_idx = dt > 0;
velocity = zeros(length(dt), 1);

% Absolute yaw per second
velocity(valid_idx) = abs(dyaw(valid_idx) ./ dt(valid_idx));
valid_time = time(valid_idx);

% --- ANOMALY FIX: Restrict peak search window ---
% Only look for the peak velocity BEFORE 3.5 seconds to ignore late resets
search_window_idx = find(valid_time <= 3.5); 

if isempty(search_window_idx)
    search_window_idx = 1:length(velocity);
end

% Step 1: Find the absolute peak velocity of the main movement *only* within the window
[max_vel, relative_peak_idx] = max(velocity(search_window_idx));

% Convert that relative index back to the full velocity array index
peak_idx = search_window_idx(relative_peak_idx);

% --- THRESHOLD RANGE: 0.5 to 7.5 deg/s in 0.5 increments ---
thresholds = 0.5:0.5:7.5;

for thr = thresholds
    % If they never reached this speed during the main turn, skip
    if max_vel < thr
        continue;
    end
    
    % Step 2: Only look at the velocity array AFTER the valid peak
    vel_after_peak = velocity(peak_idx:end);
    
    % Step 3: Find the EXACT frame it drops below the threshold on the way down
    cross_idx_relative = find(vel_after_peak < thr, 1, 'first');
    
    if ~isempty(cross_idx_relative)
        % Convert relative index back to the full array index
        trans_idx = peak_idx + cross_idx_relative - 1;
        
        end_idx = length(yaw);
        
        % Wrap-around subtraction ensures over-rotation is positive and under-rotation is negative
        raw_diff = yaw(end_idx) - yaw(trans_idx);
        
        % Converted to Absolute Value
        total_rotation = abs(mod(raw_diff + 180, 360) - 180);
        
        duration = time(end_idx) - time(trans_idx);
        
        % Added targetDeg to the table so the plotting loop can access it
        newRow = table(trialIdx, {location}, thr, total_rotation, duration, targetDeg, ...
            'VariableNames', {'Trial', 'Location', 'Threshold', 'TotalRotation', 'Duration', 'TargetDeg'});
        
        results = [results; newRow];
    end
end

end
