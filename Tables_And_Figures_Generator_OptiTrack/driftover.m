%% ============================================================
%  CSV COMPARISON: DRIFT ENCODE vs PROD (ABS VALUES, COMBINED FIGURE)
%% ============================================================

%% --- STEP 1: FILE SELECTION & LOADING ---------------------
csv_files = {
    'P001_1_2026-06-15_164413_Results.csv';
    'P001_1_2026-06-19_164348_Results.csv';
    'P001_1_2026-06-19_161428_Results.csv';
    'P001_2_2026-06-15_165401_Results.csv';
};

fprintf('\n%s\n', repmat('=', 1, 100));
fprintf('CSV COMPARISON PIPELINE: ABSOLUTE DRIFT METRICS\n');
fprintf('%s\n', repmat('=', 1, 100));

% Initialize all_data as an empty table
all_data = table(); 

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
        fprintf('✓ Loaded: %s  (n=%d trials)\n', csv_files{i}, height(data_table));
    else
        fprintf('✗ File not found: %s\n', csv_files{i});
    end
end

% Filter for accepted trials only
if ismember('Status', all_data.Properties.VariableNames)
    data = all_data(strcmp(all_data.Status, 'Accepted'), :);
else
    data = all_data;
end
fprintf('\nTotal accepted trials: %d\n', height(data));

%% --- STEP 2: EXTRACT VARIABLES & CLEAN NANS ----------------------------
q_type = table2array(data(:, 'Q')); 

% Applied abs() to convert vector drift into absolute magnitude
enc_head = abs(table2array(data(:, 'EncodeDriftHead')));
prd_head = abs(table2array(data(:, 'ProdDriftHead')));

enc_torso = abs(table2array(data(:, 'EncodeDriftTorso')));
prd_torso = abs(table2array(data(:, 'ProdDriftTorso')));

% Setup structures to hold segmented categories
questions = {'Q1', 'Q2', 'Q3', 'Q4'};
head_data = struct();
torso_data = struct();

for i = 1:numel(questions)
    q = questions{i};
    idx = strcmp(q_type, q);
    
    % Head slices + Clean NaNs
    head_data.(q).enc = enc_head(idx); head_data.(q).enc(isnan(head_data.(q).enc)) = [];
    head_data.(q).prd = prd_head(idx); head_data.(q).prd(isnan(head_data.(q).prd)) = [];
    
    % Torso slices + Clean NaNs
    torso_data.(q).enc = enc_torso(idx); torso_data.(q).enc(isnan(torso_data.(q).enc)) = [];
    torso_data.(q).prd = prd_torso(idx); torso_data.(q).prd(isnan(torso_data.(q).prd)) = [];
end

%% --- STEP 3: DESCRIPTIVE STATISTICS ------------------------------------
fprintf('\n%s\n', repmat('=', 1, 100));
fprintf('DESCRIPTIVE STATISTICS SUMMARY (ABSOLUTE DRIFT)\n');
fprintf('%s\n', repmat('=', 1, 100));

% Print Head Summary Table
fprintf('--- HEAD DRIFT METRICS (ABS) ---\n');
fprintf('%-15s  %6s  %12s  %12s  |  %6s  %12s  %12s\n', 'Question', 'N_Enc', 'Mean_Enc', 'SD_Enc', 'N_Prd', 'Mean_Prd', 'SD_Prd');
fprintf('%s\n', repmat('-', 1, 90));
for i = 1:numel(questions)
    q = questions{i};
    fprintf('%-15s  %6d  %12.2f  %12.2f  |  %6d  %12.2f  %12.2f\n', q, ...
        numel(head_data.(q).enc), mean(head_data.(q).enc), std(head_data.(q).enc), ...
        numel(head_data.(q).prd), mean(head_data.(q).prd), std(head_data.(q).prd));
end

% Print Torso Summary Table
fprintf('\n--- TORSO DRIFT METRICS (ABS) ---\n');
fprintf('%-15s  %6s  %12s  %12s  |  %6s  %12s  %12s\n', 'Question', 'N_Enc', 'Mean_Enc', 'SD_Enc', 'N_Prd', 'Mean_Prd', 'SD_Prd');
fprintf('%s\n', repmat('-', 1, 90));
for i = 1:numel(questions)
    q = questions{i};
    fprintf('%-15s  %6d  %12.2f  %12.2f  |  %6d  %12.2f  %12.2f\n', q, ...
        numel(torso_data.(q).enc), mean(torso_data.(q).enc), std(torso_data.(q).enc), ...
        numel(torso_data.(q).prd), mean(torso_data.(q).prd), std(torso_data.(q).prd));
end
fprintf('%s\n', repmat('=', 1, 100));

%% --- STEP 4: VISUALIZATION (COMBINED FIGURE) ---------------------------
% Define explicit x-axis positions to cluster Encode & Prod pairs
x_pos = [1.0, 1.4,  2.5, 2.9,  4.0, 4.4,  5.5, 5.9];
x_ticks = [1.2, 2.7, 4.2, 5.7];

% Create single wider figure window to cleanly host side-by-side subplots
figure('Name', 'Absolute Drift Metrics: Head vs Torso', 'NumberTitle', 'off', 'Position', [100 100 1400 550]);
set(gcf, 'PaperPositionMode', 'auto');

% --- SUBPLOT 1: HEAD PLOT ---
subplot(1, 2, 1);
hold on;
for i = 1:numel(questions)
    q = questions{i};
    p_enc = x_pos((i-1)*2 + 1);
    p_prd = x_pos((i-1)*2 + 2);
    
    % Jittered Scatters (Blue = Encode, Orange = Prod)
    h1_enc = scatter(p_enc + randn(numel(head_data.(q).enc),1)*0.03, head_data.(q).enc, 50, [0 0.447 0.741], 'filled'); 
    h1_prd = scatter(p_prd + randn(numel(head_data.(q).prd),1)*0.03, head_data.(q).prd, 50, [0.85 0.325 0.098], 'filled'); 
    
    % Horizontal Mean Bars
    plot([p_enc-0.15 p_enc+0.15], [mean(head_data.(q).enc) mean(head_data.(q).enc)], 'k-', 'LineWidth', 3);
    plot([p_prd-0.15 p_prd+0.15], [mean(head_data.(q).prd) mean(head_data.(q).prd)], 'k-', 'LineWidth', 3);
end
set(gca, 'XTick', x_ticks, 'XTickLabel', {'Q1', 'Q2', 'Q3', 'Q4'}, 'XLim', [0.5 6.4]);
ylabel('Absolute Drift Value', 'FontSize', 12);
title('Head Absolute Drift', 'FontSize', 13, 'FontWeight', 'bold');
legend([h1_enc, h1_prd], {'Encode', 'Prod'}, 'Location', 'northeast');
grid on; hold off;

% --- SUBPLOT 2: TORSO PLOT ---
subplot(1, 2, 2);
hold on;
for i = 1:numel(questions)
    q = questions{i};
    p_enc = x_pos((i-1)*2 + 1);
    p_prd = x_pos((i-1)*2 + 2);
    
    % Jittered Scatters (Blue = Encode, Orange = Prod)
    h2_enc = scatter(p_enc + randn(numel(torso_data.(q).enc),1)*0.03, torso_data.(q).enc, 50, [0 0.447 0.741], 'filled'); 
    h2_prd = scatter(p_prd + randn(numel(torso_data.(q).prd),1)*0.03, torso_data.(q).prd, 50, [0.85 0.325 0.098], 'filled'); 
    
    % Horizontal Mean Bars
    plot([p_enc-0.15 p_enc+0.15], [mean(torso_data.(q).enc) mean(torso_data.(q).enc)], 'k-', 'LineWidth', 3);
    plot([p_prd-0.15 p_prd+0.15], [mean(torso_data.(q).prd) mean(torso_data.(q).prd)], 'k-', 'LineWidth', 3);
end
set(gca, 'XTick', x_ticks, 'XTickLabel', {'Q1', 'Q2', 'Q3', 'Q4'}, 'XLim', [0.5 6.4]);
ylabel('Absolute Drift Value', 'FontSize', 12);
title('Torso Absolute Drift', 'FontSize', 13, 'FontWeight', 'bold');
legend([h2_enc, h2_prd], {'Encode', 'Prod'}, 'Location', 'northeast');
grid on; hold off;

% Super title across the entire figure canvas
sgtitle('Absolute Drift Profiles: Encode vs Prod Comparison', 'FontSize', 15, 'FontWeight', 'bold');
