%% ============================================================
%  CSV COMPARISON: ENCODE TIME BY QUESTION (Q1, Q2, Q3, Q4)
%% ============================================================

%% --- STEP 1: FILE SELECTION & LOADING ---------------------
csv_files = {
    'P001_1_2026-06-15_164413_Results.csv';
    'P001_1_2026-06-19_161428_Results.csv';
    'P001_1_2026-06-19_164348_Results.csv';
    'P001_2_2026-06-15_165401_Results.csv';
};

fprintf('\n%s\n', repmat('=', 1, 100));
fprintf('CSV COMPARISON PIPELINE: ENCODE TIME METRICS\n');
fprintf('%s\n', repmat('=', 1, 100));

% Initialize all_data as an empty table
all_data = table(); 
participant_ids = {};

for i = 1:numel(csv_files)
    if exist(csv_files{i}, 'file')
        data_table = readtable(csv_files{i});
        
        % Handle mismatched table columns gracefully
        if isempty(all_data)
            all_data = data_table; 
        else
            common_vars = intersect(all_data.Properties.VariableNames, data_table.Properties.VariableNames, 'stable');
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
if ismember('Status', all_data.Properties.VariableNames)
    data = all_data(strcmp(all_data.Status, 'Accepted'), :);
else
    fprintf('Warning: "Status" column missing! Using all trials.\n');
    data = all_data;
end

N = height(data);
fprintf('\nTotal accepted trials: %d\n', N);

%% --- STEP 2: EXTRACT VARIABLES & CLEAN NANS ----------------------------
% FIX: Updated to use the truncated column names 'EncodeTim' and 'Q'
encode_time = table2array(data(:, 'EncodeTime'));
q_type = table2array(data(:, 'Q')); 

is_phys = strcmp(task_type, 'P');
... 

% Filter metrics per unique Question type and strip NaNs
et_q1 = encode_time(strcmp(q_type, 'Q1'));
et_q1 = et_q1(~isnan(et_q1));

et_q2 = encode_time(strcmp(q_type, 'Q2'));
et_q2 = et_q2(~isnan(et_q2));

et_q3 = encode_time(strcmp(q_type, 'Q3'));
et_q3 = et_q3(~isnan(et_q3));

et_q4 = encode_time(strcmp(q_type, 'Q4'));
et_q4 = et_q4(~isnan(et_q4));

%% --- STEP 3: DESCRIPTIVE STATISTICS (MEANS & SDs) ----------------------
fprintf('\n%s\n', repmat('=', 1, 100));
fprintf('ENCODE TIME DESCRIPTIVE SUMMARY\n');
fprintf('%s\n', repmat('=', 1, 100));

fprintf('%-25s  %8s  %12s  %12s\n', 'Condition', 'N', 'Mean (s)', 'SD (s)');
fprintf('%s\n', repmat('-', 1, 65));

fprintf('%-25s  %8d  %12.2f  %12.2f\n', 'Question 1 (Q1)', numel(et_q1), mean(et_q1), std(et_q1));
fprintf('%-25s  %8d  %12.2f  %12.2f\n', 'Question 2 (Q2)', numel(et_q2), mean(et_q2), std(et_q2));
fprintf('%-25s  %8d  %12.2f  %12.2f\n', 'Question 3 (Q3)', numel(et_q3), mean(et_q3), std(et_q3));
fprintf('%-25s  %8d  %12.2f  %12.2f\n', 'Question 4 (Q4)', numel(et_q4), mean(et_q4), std(et_q4));
fprintf('%s\n', repmat('=', 1, 100));

%% --- STEP 5: VISUALIZATION --------------------------------
figure('Name', 'Encode Time Comparison by Question', 'NumberTitle', 'off', 'Position', [100 100 800 500]);
hold on;

% Jitter and plot scatter data points
scatter(ones(numel(et_q1),1) + randn(numel(et_q1),1)*0.04, et_q1, 60, [0 0.447 0.741], 'filled'); % Blue
scatter(2*ones(numel(et_q2),1) + randn(numel(et_q2),1)*0.04, et_q2, 60, [0.85 0.325 0.098], 'filled'); % Orange
scatter(3*ones(numel(et_q3),1) + randn(numel(et_q3),1)*0.04, et_q3, 60, [0.929 0.694 0.125], 'filled'); % Yellow
scatter(4*ones(numel(et_q4),1) + randn(numel(et_q4),1)*0.04, et_q4, 60, [0.494 0.184 0.556], 'filled'); % Purple

% Plot Horizontal Mean lines 
plot([0.7 1.3], [mean(et_q1) mean(et_q1)], 'k-', 'LineWidth', 3);
plot([1.7 2.3], [mean(et_q2) mean(et_q2)], 'k-', 'LineWidth', 3);
plot([2.7 3.3], [mean(et_q3) mean(et_q3)], 'k-', 'LineWidth', 3);
plot([3.7 4.3], [mean(et_q4) mean(et_q4)], 'k-', 'LineWidth', 3);

% Formatting the axes
set(gca, 'XTick', 1:4, 'XTickLabel', {'Q1', 'Q2', 'Q3', 'Q4'}, 'XLim', [0.5 4.5]);
ylabel('Encode Time (seconds)', 'FontSize', 12);
title('Encode Time Distribution across Questions', 'FontSize', 13, 'FontWeight', 'bold');
grid on;
hold off;
