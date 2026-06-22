%% --- STEP 1: FILE SELECTION & LOADING ---------------------
csv_files = {
    'P001_1_2026-06-15_164413_Results.csv';
    'P001_1_2026-06-19_161428_Results.csv';
    'P001_1_2026-06-19_164348_Results.csv';
    'P001_2_2026-06-15_165401_Results.csv';
};
fprintf('\n%s\n', repmat('=', 1, 100));
fprintf('CSV COMPARISON PIPELINE: TIMING METRICS\n');
fprintf('%s\n', repmat('=', 1, 100));

% Initialize all_data as an empty table, not an empty double array []
all_data = table(); 
participant_ids = {};

for i = 1:numel(csv_files)
    if exist(csv_files{i}, 'file')
        data_table = readtable(csv_files{i});
        
        % FIX: Handle mismatched table columns gracefully
        if isempty(all_data)
            all_data = data_table; % First iteration establishes the base table
        else
            % Find common column names between the existing data and the new table
            common_vars = intersect(all_data.Properties.VariableNames, data_table.Properties.VariableNames, 'stable');
            
            % Vertically concatenate keeping ONLY the intersecting columns
            all_data = [all_data(:, common_vars); data_table(:, common_vars)];
        end
        
        [~, filename, ~] = fileparts(csv_files{i});
        parts = strsplit(filename, '_');
        participant_ids{i} = parts{1};
        
        fprintf('✓ Loaded: %s  (n=%d trials)\n', csv_files{i}, height(data_table));
    else
        fprintf('✗ File not found: %s\n', csv_files{i});
    end
end

% Filter for accepted trials only
% (Added a check just in case the 'Status' column is ever missing)
if ismember('Status', all_data.Properties.VariableNames)
    data = all_data(strcmp(all_data.Status, 'Accepted'), :);
else
    fprintf('Warning: "Status" column missing! Using all trials.\n');
    data = all_data;
end

N = height(data);
fprintf('\nTotal accepted trials: %d\n', N);

%% --- STEP 2: EXTRACT VARIABLES ----------------------------

walk_time = table2array(data(:, 'WalkTime'));
imag_time = table2array(data(:, 'RT_ImagWalk'));
rt_rot = table2array(data(:, 'RT_Rot'));
task_type = table2array(data(:, 'Type'));

is_phys = strcmp(task_type, 'P');
is_imag = strcmp(task_type, 'I');

walk_time_phys = walk_time(is_phys);
walk_time_imag = walk_time(is_imag);
imag_time_phys = imag_time(is_phys);
imag_time_imag = imag_time(is_imag);
rt_rot_phys = rt_rot(is_phys);
rt_rot_imag = rt_rot(is_imag);

%% --- STEP 3: DESCRIPTIVE STATISTICS ----------------------
fprintf('\n%s\n', repmat('=', 1, 100));
fprintf('TIMING METRICS SUMMARY\n');
fprintf('%s\n', repmat('=', 1, 100));

fprintf('\n--- WALKING TIME vs IMAGINED WALKING TIME ---\n');
fprintf('%-40s  %8s  %10s  %10s  %10s\n', 'Metric', 'N', 'Mean (s)', 'SD (s)', 'Range');
fprintf('%s\n', repmat('-', 1, 85));

fprintf('%-40s  %8d  %10.2f  %10.2f  [%.2f - %.2f]\n', ...
    'Physical Walking Time', numel(walk_time_phys), mean(walk_time_phys), std(walk_time_phys), ...
    min(walk_time_phys), max(walk_time_phys));

fprintf('%-40s  %8d  %10.2f  %10.2f  [%.2f - %.2f]\n', ...
    'Imagined Walking Time (Physical Trials)', numel(imag_time_phys), mean(imag_time_phys), std(imag_time_phys), ...
    min(imag_time_phys), max(imag_time_phys));

fprintf('%-40s  %8d  %10.2f  %10.2f  [%.2f - %.2f]\n', ...
    'Imagined Walking Time (Imagined Trials)', numel(imag_time_imag), mean(imag_time_imag), std(imag_time_imag), ...
    min(imag_time_imag), max(imag_time_imag));

fprintf('\n--- RESPONSE ROTATION TIME (RT_Rot) ---\n');
fprintf('%-40s  %8s  %10s  %10s  %10s\n', 'Condition', 'N', 'Mean (s)', 'SD (s)', 'Range');
fprintf('%s\n', repmat('-', 1, 85));

fprintf('%-40s  %8d  %10.2f  %10.2f  [%.2f - %.2f]\n', ...
    'Physical Response Rotation', numel(rt_rot_phys), mean(rt_rot_phys), std(rt_rot_phys), ...
    min(rt_rot_phys), max(rt_rot_phys));

fprintf('%-40s  %8d  %10.2f  %10.2f  [%.2f - %.2f]\n', ...
    'Imagined Response Rotation', numel(rt_rot_imag), mean(rt_rot_imag), std(rt_rot_imag), ...
    min(rt_rot_imag), max(rt_rot_imag));

%% --- STEP 4: STATISTICAL COMPARISONS ----------------------
fprintf('\n%s\n', repmat('=', 1, 100));
fprintf('STATISTICAL TESTS\n');
fprintf('%s\n', repmat('=', 1, 100));

fprintf('\n--- COMPARISON 1: Walking Time vs Imagined Time (Physical Trials) ---\n');
if numel(walk_time_phys) > 1 && numel(imag_time_phys) > 1
    try
        [t_walk_imag, p_walk_imag, df_walk_imag] = ttest2_custom(walk_time_phys, imag_time_phys);
        mean_diff = mean(walk_time_phys) - mean(imag_time_phys);
        d = cohens_d(walk_time_phys, imag_time_phys);
        
        fprintf('Physical Walking Time:  %.2f ± %.2f s\n', mean(walk_time_phys), std(walk_time_phys));
        fprintf('Imagined Walking Time:  %.2f ± %.2f s\n', mean(imag_time_phys), std(imag_time_phys));
        fprintf('Mean Difference:        %.2f s\n', mean_diff);
        fprintf('t(%.0f) = %.3f, p = %.4f  %s\n', df_walk_imag, t_walk_imag, p_walk_imag, sig_stars(p_walk_imag));
        fprintf('Cohen''s d = %.3f\n', d);
    catch
        fprintf('(Insufficient data for statistical test)\n');
    end
else
    fprintf('(Insufficient data for statistical test)\n');
end

fprintf('\n--- COMPARISON 2: Response Rotation Time (Physical vs Imagined) ---\n');
if numel(rt_rot_phys) > 1 && numel(rt_rot_imag) > 1
    try
        [t_rot, p_rot, df_rot] = ttest2_custom(rt_rot_phys, rt_rot_imag);
        mean_diff_rot = mean(rt_rot_phys) - mean(rt_rot_imag);
        d_rot = cohens_d(rt_rot_phys, rt_rot_imag);
        
        fprintf('Physical Response Time:  %.2f ± %.2f s\n', mean(rt_rot_phys), std(rt_rot_phys));
        fprintf('Imagined Response Time:  %.2f ± %.2f s\n', mean(rt_rot_imag), std(rt_rot_imag));
        fprintf('Mean Difference:         %.2f s\n', mean_diff_rot);
        fprintf('t(%.0f) = %.3f, p = %.4f  %s\n', df_rot, t_rot, p_rot, sig_stars(p_rot));
        fprintf('Cohen''s d = %.3f\n', d_rot);
    catch
        fprintf('(Insufficient data for statistical test)\n');
    end
else
    fprintf('(Insufficient data for statistical test)\n');
end

%% --- STEP 5: VISUALIZATION --------------------------------
figure('Name', 'Timing Metrics Comparison', 'NumberTitle', 'off', 'Position', [100 100 1200 500]);
set(gcf, 'PaperPositionMode', 'auto');

% --- LEFT: Walking vs Imagined (Physical Trials) ---
subplot(1, 2, 1);
hold on;
scatter(ones(numel(walk_time_phys),1) + randn(numel(walk_time_phys),1)*0.05, walk_time_phys, 80, 'b', 'filled');
scatter(2*ones(numel(imag_time_phys),1) + randn(numel(imag_time_phys),1)*0.05, imag_time_phys, 80, 'r', 'filled');

% FIX: Reverted to walk_time_phys and imag_time_phys variables here!
plot([0.7 1.3], [mean(walk_time_phys, 'omitnan') mean(walk_time_phys, 'omitnan')], 'b-', 'LineWidth', 3);
plot([1.7 2.3], [mean(imag_time_phys, 'omitnan') mean(imag_time_phys, 'omitnan')], 'r-', 'LineWidth', 3);

set(gca, 'XTick', [1 2], 'XTickLabel', {'Walking', 'Imagined'}, 'XLim', [0.5 2.5], 'YLim', [0 15]);
ylabel('Time (seconds)', 'FontSize', 12);
title('Walking vs Imagined Time (Physical Trials)', 'FontSize', 13, 'FontWeight', 'bold');
grid on;
hold off;

% --- RIGHT: Response Rotation (Physical vs Imagined) ---
subplot(1, 2, 2);
hold on;
scatter(ones(numel(rt_rot_phys),1) + randn(numel(rt_rot_phys),1)*0.05, rt_rot_phys, 80, 'b', 'filled');
scatter(2*ones(numel(rt_rot_imag),1) + randn(numel(rt_rot_imag),1)*0.05, rt_rot_imag, 80, 'r', 'filled');

% Correctly maps response rotation variables
plot([0.7 1.3], [mean(rt_rot_phys, 'omitnan') mean(rt_rot_phys, 'omitnan')], 'b-', 'LineWidth', 3);
plot([1.7 2.3], [mean(rt_rot_imag, 'omitnan') mean(rt_rot_imag, 'omitnan')], 'r-', 'LineWidth', 3);

set(gca, 'XTick', [1 2], 'XTickLabel', {'Physical', 'Imagined'}, 'XLim', [0.5 2.5], 'YLim', [0 15]);
ylabel('Time (seconds)', 'FontSize', 12);
title('Response Rotation Time by Modality', 'FontSize', 13, 'FontWeight', 'bold');
grid on;
hold off;

sgtitle('Timing Metrics Comparison', 'FontSize', 14, 'FontWeight', 'bold');
fprintf('\n%s\n', repmat('=', 1, 100));

%% --- LOCAL FUNCTIONS ----------------------------------------
function [t_stat, p_val, df] = ttest2_custom(x, y)
    % Independent samples t-test (no Statistics Toolbox required)
    n1 = numel(x);
    n2 = numel(y);
    df = n1 + n2 - 2;
    
    m1 = mean(x);
    m2 = mean(y);
    s1 = std(x);
    s2 = std(y);
    
    s_pooled = sqrt(((n1-1)*s1^2 + (n2-1)*s2^2) / df);
    se = s_pooled * sqrt(1/n1 + 1/n2);
    
    t_stat = (m1 - m2) / se;
    p_val = 2 * tcdf_approx(abs(t_stat), df);
end

function p = tcdf_approx(t, df)
    % Approximate t-distribution CDF using incomplete beta function
    t = abs(t);
    p_upper = betainc(df/(df + t^2), df/2, 0.5) / 2;
    p = 1 - p_upper;
end

function d = cohens_d(group1, group2)
    % Cohen's d effect size
    n1 = numel(group1);
    n2 = numel(group2);
    pooled_sd = sqrt(((n1-1)*std(group1)^2 + (n2-1)*std(group2)^2) / (n1 + n2 - 2));
    d = (mean(group1) - mean(group2)) / pooled_sd;
end

function s = sig_stars(p)
    % Significance stars
    if p < 0.001, s = '***';
    elseif p < 0.01, s = '**';
    elseif p < 0.05, s = '*';
    elseif p < 0.10, s = '†';
    else, s = '(ns)';
    end
end
