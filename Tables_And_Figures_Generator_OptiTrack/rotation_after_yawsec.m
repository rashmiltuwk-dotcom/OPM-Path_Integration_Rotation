%% ROTATION ANALYSIS
% Assumes 'MasterData' is already loaded in your workspace!
% Analyzes absolute velocity AFTER dynamic start index based on target
% Anchors to PEAK velocity to prevent false-positive early jitters

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

for i = 1:N
    tr = accepted(i);
    targetDeg = tr.TargetDeg; 
    
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

fprintf('Processed %d trials, extracted post-peak decelerations.\n\n', N);

%% --- SUMMARY STATISTICS ---
fprintf('%s\n', repmat('=', 1, 70));
fprintf('ROTATION ANALYSIS SUMMARY (Post-Peak Rotation)\n');
fprintf('%s\n\n', repmat('=', 1, 70));

threshold_values = 5:5:50;
locations = {'head', 'torso'};

for loc_idx = 1:length(locations)
    location = locations{loc_idx};
    fprintf('%s ROTATION:\n', upper(location));
    fprintf('%s\n', repmat('-', 1, 70));
    
    for thr = threshold_values
        mask = strcmp(results.Location, location) & (results.Threshold == thr);
        filtered = results.TotalRotation(mask);
        
        if ~isempty(filtered)
            fprintf('\n  Threshold: %d deg/s\n', thr);
            fprintf('    Count: %d\n', length(filtered));
            fprintf('    Mean Rotation: %.4f°\n', mean(filtered));
            fprintf('    Rotation Range: [%.4f, %.4f]°\n', min(filtered), max(filtered));
        end
    end
    fprintf('\n');
end

%% --- PLOTS (Custom Boxplot for Total Rotation) ---
fprintf('Creating plots...\n');

figure('Name', 'Rotation Analysis', 'Color', 'w', 'Position', [100 100 1400 600]);

for loc_idx = 1:2
    subplot(1, 2, loc_idx);
    location = locations{loc_idx};
    hold on;
    
    plot_labels = {};
    x_positions = [];
    
    for thr_idx = 1:length(threshold_values)
        thr = threshold_values(thr_idx);
        mask = strcmp(results.Location, location) & (results.Threshold == thr);
        
        filtered = results.TotalRotation(mask);
        targets = results.TargetDeg(mask); % Extract the targets for these specific points
        
        if ~isempty(filtered)
            x_positions = [x_positions, thr_idx];
            plot_labels{end+1} = sprintf('%d', thr);
            
            % Add random jitter to X so points don't completely overlap
            x_jitter = thr_idx + (rand(length(filtered), 1) - 0.5) * 0.3;
            
            % --- COLOR CODING LOGIC ---
            green_mask = (targets == 60) | (targets == 300) | (targets == 360);
            yellow_mask = (targets == 120) | (targets == 240);
            other_mask = ~(green_mask | yellow_mask);
            
            % Plot standard trials (Blue)
            if any(other_mask)
                scatter(x_jitter(other_mask), filtered(other_mask), 30, [0.2 0.4 0.8], 'filled', 'MarkerFaceAlpha', 0.5);
            end
            
            % Plot 60, 300, and 360 TargetDeg (Green)
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
        set(gca, 'XTick', x_positions, 'XTickLabel', plot_labels, 'FontSize', 11);
    end
    
    proper_title_case = [upper(location(1)), location(2:end)];
    
    xlabel('Absolute Velocity Threshold (deg/s)', 'FontWeight', 'bold', 'FontSize', 11);
    ylabel('Absolute End of Epoch Rotation (degrees)', 'FontWeight', 'bold', 'FontSize', 11);
    title(sprintf('%s - Post-Peak Deceleration Rotation', proper_title_case), 'FontWeight', 'bold', 'FontSize', 12);
    grid on; grid minor;
    hold off;
end

sgtitle('Absolute Total Rotation From Threshold Crossing to End of Epoch', 'FontWeight', 'bold', 'FontSize', 14);
fprintf('Done!\n\n');

%% ========================================================================
function results = analyzeTrace(trace, trialIdx, location, targetDeg)
    
results = table();
original_time = trace.time(:);
yaw = trace.yaw(:);

% Determine Start Index based on the target degrees
if targetDeg == 60 || targetDeg == 300 || targetDeg == 360
    START_IDX = 75;
elseif targetDeg == 120 || targetDeg == 240
    START_IDX = 150;
end

% Ensure trace is long enough before proceeding
if length(original_time) <= START_IDX
    fprintf('Skipping Trial %d (%s): Only %d data points, needed %d.\n', trialIdx, location, length(original_time), START_IDX);
    return;
end

time = original_time(START_IDX:end);
yaw = yaw(START_IDX:end);

dt = diff(time);
dyaw = diff(yaw);

valid_idx = dt > 0;
velocity = zeros(length(dt), 1);

% Absolute yaw per second
velocity(valid_idx) = abs(dyaw(valid_idx) ./ dt(valid_idx));

% Step 1: Find the absolute peak velocity of the main movement
[max_vel, peak_idx] = max(velocity);

thresholds = 5:5:50;

for thr = thresholds
    % If they never reached this speed, skip to prevent garbage data
    if max_vel < thr
        continue;
    end
    
    % Step 2: Only look at the velocity array AFTER the peak
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
