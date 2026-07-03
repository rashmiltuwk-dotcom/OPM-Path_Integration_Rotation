%% --- PER-PARTICIPANT TIMING ANALYSIS ---
% Reads CSV files inside *Results folders, groups by participant ID

folderPath = 'C:\Users\spaceandmem\rashmil_opm\grouped_data';

participantFolders = dir(fullfile(folderPath, 'p*'));
participantFolders = participantFolders([participantFolders.isdir]);

fprintf('\n%s\n', repmat('=', 1, 100));
fprintf('PER-PARTICIPANT TIMING ANALYSIS\n');
fprintf('%s\n\n', repmat('=', 1, 100));

all_files = {};

for p = 1:length(participantFolders)
    participantPath = fullfile(participantFolders(p).folder, participantFolders(p).name);
    
    % Debug: show actual path and all files
    allFiles = dir(participantPath);
    allFiles = allFiles(~[allFiles.isdir]);
    
    % Find *_Results.csv FILES
    resultsFiles = dir(fullfile(participantPath, '*_Results.csv'));
    
    if length(allFiles) > 0
        fprintf('%s: %d total files, %d _Results.csv files - Files: ', participantFolders(p).name, length(allFiles), length(resultsFiles));
        for i = 1:min(3, length(allFiles))
            fprintf('%s ', allFiles(i).name);
        end
        fprintf('\n');
    end
    
    for rf = 1:length(resultsFiles)
        fullFileName = fullfile(resultsFiles(rf).folder, resultsFiles(rf).name);
        
        % Extract participant from FOLDER name (p001, p002, etc.), not filename
        file_participant = lower(participantFolders(p).name);
        
        try
            % Files have .csv extension now, so readtable can auto-detect
            data_table = readtable(fullFileName);
            
            if height(data_table) > 0
                all_files{end+1, 1} = file_participant;
                all_files{end, 2} = resultsFiles(rf).name;
                all_files{end, 3} = data_table;
                fprintf('  ✓ %s (%s, %d rows)\n', resultsFiles(rf).name, file_participant, height(data_table));
            end
        catch ME
            fprintf('  ✗ %s: %s\n', resultsFiles(rf).name, ME.message);
        end
    end
end

if isempty(all_files)
    error('No files loaded successfully.');
end

% Get unique participants and assign colors
unique_participants = unique(all_files(:, 1));
colors = lines(length(unique_participants));

fprintf('Files loaded by participant:\n');
for p = 1:length(unique_participants)
    n_files = sum(strcmp(all_files(:, 1), unique_participants{p}));
    fprintf('  %s: %d file(s)\n', upper(unique_participants{p}), n_files);
end
fprintf('\nTotal unique participants: %d\n\n', length(unique_participants));

fprintf('\nCreating combined visualization for all participants...\n\n');

% Prepare combined data
all_walk_time = [];
all_rt_rot = [];
all_is_phys = [];
all_participant_colors = [];
all_is_imag = [];

% Collect data from all participants
for p_idx = 1:length(unique_participants)
    pid = unique_participants{p_idx};
    
    p_indices = find(strcmp(all_files(:, 1), pid));
    
    % Merge all files for this participant
    p_data = [];
    for idx = p_indices'
        current_table = all_files{idx, 3};
        cols_to_keep = intersect(current_table.Properties.VariableNames, {'WalkTime', 'RT_Rot', 'Type', 'Status'});
        simplified_table = current_table(:, cols_to_keep);
        
        if isempty(p_data)
            p_data = simplified_table;
        else
            missing_in_new = setdiff(p_data.Properties.VariableNames, simplified_table.Properties.VariableNames);
            for m = 1:length(missing_in_new)
                simplified_table.(missing_in_new{m}) = cell(height(simplified_table), 1);
            end
            missing_in_old = setdiff(simplified_table.Properties.VariableNames, p_data.Properties.VariableNames);
            for m = 1:length(missing_in_old)
                p_data.(missing_in_old{m}) = cell(height(p_data), 1);
            end
            p_data = [p_data; simplified_table];
        end
    end
    
    % Filter accepted
    if ismember('Status', p_data.Properties.VariableNames)
        p_data = p_data(strcmp(p_data.Status, 'Accepted'), :);
    end
    
    % Extract and clean - ensure column vectors
    walk_time = table2array(p_data(:, 'WalkTime'));
    if isrow(walk_time), walk_time = walk_time'; end
    rt_rot = table2array(p_data(:, 'RT_Rot'));
    if isrow(rt_rot), rt_rot = rt_rot'; end
    task_type = table2array(p_data(:, 'Type'));
    
    is_phys = strcmp(task_type, 'P');
    is_imag = strcmp(task_type, 'I');
    if isrow(is_phys), is_phys = is_phys'; end
    if isrow(is_imag), is_imag = is_imag'; end
    
    % Add to combined arrays - ensure column vectors
    all_walk_time = [all_walk_time; walk_time(:)];
    all_rt_rot = [all_rt_rot; rt_rot(:)];
    all_is_phys = [all_is_phys; is_phys(:)];
    all_is_imag = [all_is_imag; is_imag(:)];
    all_participant_colors = [all_participant_colors; repmat(colors(p_idx, :), height(p_data), 1)];
end

% Remove outliers: 3 SD from the mean, computed per condition (Physical / Imagined)
% on the pooled data across all participants. Doing this per-participant on small
% samples lets a single extreme value inflate its own mean/SD and mask itself, so
% it is done here instead, after all participants are combined.
all_walk_time = remove_outliers_3sd(all_walk_time, all_is_phys);
all_walk_time = remove_outliers_3sd(all_walk_time, all_is_imag);
all_rt_rot = remove_outliers_3sd(all_rt_rot, all_is_phys);
all_rt_rot = remove_outliers_3sd(all_rt_rot, all_is_imag);

% Create single combined figure
fig = figure('Name', 'All Participants - Timing Comparison', 'NumberTitle', 'off', 'Position', [100 100 1400 500]);

% Left: Walking time
subplot(1, 2, 1);
hold on;
for i = 1:length(all_walk_time)
    if all_is_phys(i)
        x_pos = 1 + randn()*0.02;
    else
        x_pos = 2 + randn()*0.02;
    end
    scatter(x_pos, all_walk_time(i), 50, all_participant_colors(i, :), 'filled', 'HandleVisibility', 'off');
end
plot([0.7 1.3], [mean(all_walk_time(all_is_phys == 1), 'omitnan') mean(all_walk_time(all_is_phys == 1), 'omitnan')], 'k-', 'LineWidth', 2, 'HandleVisibility', 'off');
plot([1.7 2.3], [mean(all_walk_time(all_is_imag == 1), 'omitnan') mean(all_walk_time(all_is_imag == 1), 'omitnan')], 'k-', 'LineWidth', 2, 'HandleVisibility', 'off');
set(gca, 'XTick', [1 2], 'XTickLabel', {'Physical', 'Imagined'}, 'XLim', [0.5 2.5]);
ylabel('Time (s)');
title('Walking Time - All Participants');
grid on;

% Legend entries: one dummy point per participant, labeled by folder name
legend_handles = gobjects(1, length(unique_participants));
for p_idx = 1:length(unique_participants)
    legend_handles(p_idx) = scatter(NaN, NaN, 50, colors(p_idx, :), 'filled', ...
        'DisplayName', upper(unique_participants{p_idx}));
end
legend(legend_handles, 'Location', 'eastoutside');
hold off;

% Right: Response rotation time
subplot(1, 2, 2);
hold on;
for i = 1:length(all_rt_rot)
    if all_is_phys(i)
        x_pos = 1 + randn()*0.02;
    else
        x_pos = 2 + randn()*0.02;
    end
    scatter(x_pos, all_rt_rot(i), 50, all_participant_colors(i, :), 'filled', 'HandleVisibility', 'off');
end
plot([0.7 1.3], [mean(all_rt_rot(all_is_phys == 1), 'omitnan') mean(all_rt_rot(all_is_phys == 1), 'omitnan')], 'k-', 'LineWidth', 2, 'HandleVisibility', 'off');
plot([1.7 2.3], [mean(all_rt_rot(all_is_imag == 1), 'omitnan') mean(all_rt_rot(all_is_imag == 1), 'omitnan')], 'k-', 'LineWidth', 2, 'HandleVisibility', 'off');
set(gca, 'XTick', [1 2], 'XTickLabel', {'Physical', 'Imagined'}, 'XLim', [0.5 2.5]);
ylabel('Time (s)');
title('Response Rotation Time - All Participants');
grid on;

legend_handles2 = gobjects(1, length(unique_participants));
for p_idx = 1:length(unique_participants)
    legend_handles2(p_idx) = scatter(NaN, NaN, 50, colors(p_idx, :), 'filled', ...
        'DisplayName', upper(unique_participants{p_idx}));
end
legend(legend_handles2, 'Location', 'eastoutside');
hold off;

sgtitle('All Participants - Timing Metrics Comparison', 'FontSize', 14, 'FontWeight', 'bold');

fprintf('\nAnalysis complete - figure displayed.\n');

function data = remove_outliers_3sd(data, condition_mask)
    % NaNs out values more than 3 SD from the mean, computed only within
    % the rows where condition_mask is true (e.g. just the Physical trials).
    condition_mask = logical(condition_mask);
    subset = data(condition_mask);
    valid = ~isnan(subset) & ~isinf(subset);
    m = mean(subset(valid));
    s = std(subset(valid));
    is_outlier = abs(subset - m) > 3*s;
    subset(is_outlier) = NaN;
    data(condition_mask) = subset;
end
