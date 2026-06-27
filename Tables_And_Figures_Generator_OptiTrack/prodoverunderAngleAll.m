%% ============================================================
%  ACCURACY SUMMARY: PRODUCTION ERROR MEAN & SD (DEGREES)
%  BY INDIVIDUAL ENCODING TARGET: [60, 120, 240, 300]
%% ============================================================

%% --- STEP 1: DATA EXTRACTION ---
accepted = MasterData(strcmp({MasterData.Status}, 'Accepted'));
N = numel(accepted);
if N == 0, error('No accepted trials in MasterData.'); end

% Initialize storage
prod_err_t = NaN(N,1); prod_err_h = NaN(N,1);
modality = cell(N,1); enc_targ = NaN(N,1);

for i = 1:N
    tr = accepted(i);
    modality{i} = tr.TaskType;
    enc_targ(i) = tr.TargetDeg;
    
    % Production Absolute Errors (with wrap-around)
    if strcmp(tr.TaskType, 'P')
        if ismember(tr.TargetDeg, [60, 300]), rTarget = 120; else, rTarget = 60; end
        yProdT = tr.Traces.ResponseRotationTorsoTrace.yaw;
        yProdH = tr.Traces.ResponseRotationHeadTrace.yaw;
        % Calculate absolute displacement (magnitude only)
        dispProdT = abs(mod(yProdT(end) - yProdT(1) + 180, 360) - 180);
        dispProdH = abs(mod(yProdH(end) - yProdH(1) + 180, 360) - 180);
        % Error is absolute difference from target
        prod_err_t(i) = abs(mod(dispProdT - rTarget + 180, 360) - 180);
        prod_err_h(i) = abs(mod(dispProdH - rTarget + 180, 360) - 180);
    end
end

%% --- STEP 2: PRODUCTION SUMMARY (INDIVIDUAL TARGETS) ---
fprintf('\n--- PRODUCTION ERROR (INDIVIDUAL): MEAN ± SD (DEGREES) ---\n');
fprintf('%-20s | %-15s | %-15s | %-10s\n', 'Encoding Target', 'Torso (°)', 'Head (°)', 'Response');
fprintf('-------------------------------------------------------------------\n');

is_phys = strcmp(modality, 'P');

prod_targets = [60, 120, 240, 300];
prod_mean_t = NaN(4,1); prod_sd_t = NaN(4,1);
prod_mean_h = NaN(4,1); prod_sd_h = NaN(4,1);

for i = 1:4
    target = prod_targets(i);
    idx = (enc_targ == target) & is_phys;
    t_p_vals = prod_err_t(idx);
    h_p_vals = prod_err_h(idx);
    
    if ~isempty(t_p_vals) && ~all(isnan(t_p_vals))
        prod_mean_t(i) = mean(t_p_vals); 
        prod_sd_t(i) = std(t_p_vals);
        prod_mean_h(i) = mean(h_p_vals); 
        prod_sd_h(i) = std(h_p_vals);
        
        % Determine response target
        if ismember(target, [60, 300])
            rTarget = 120;
        else
            rTarget = 60;
        end
        
        fprintf('%-20s | %5.2f ± %4.2f | %5.2f ± %4.2f | %d°\n', ...
            sprintf('%d°', target), prod_mean_t(i), prod_sd_t(i), prod_mean_h(i), prod_sd_h(i), rTarget);
    end
end

%% --- STEP 2B: PRODUCTION SUMMARY (GROUPED TARGETS) ---
fprintf('\n--- PRODUCTION ERROR (GROUPED): MEAN ± SD (DEGREES) ---\n');
fprintf('%-20s | %-15s | %-15s\n', 'Group', 'Torso (°)', 'Head (°)');
fprintf('-------------------------------------------------------------\n');

prod_groups = {[60, 300], [120, 240]};
prod_group_names = {'60°/300° -> 120°', '120°/240° -> 60°'};
prod_mean_t_grp = NaN(2,1); prod_sd_t_grp = NaN(2,1);
prod_mean_h_grp = NaN(2,1); prod_sd_h_grp = NaN(2,1);

for i = 1:2
    idx = ismember(enc_targ, prod_groups{i}) & is_phys;
    t_p_vals = prod_err_t(idx);
    h_p_vals = prod_err_h(idx);
    prod_mean_t_grp(i) = mean(t_p_vals); prod_sd_t_grp(i) = std(t_p_vals);
    prod_mean_h_grp(i) = mean(h_p_vals); prod_sd_h_grp(i) = std(h_p_vals);
    fprintf('%-20s | %5.2f ± %4.2f | %5.2f ± %4.2f\n', ...
        prod_group_names{i}, prod_mean_t_grp(i), prod_sd_t_grp(i), prod_mean_h_grp(i), prod_sd_h_grp(i));
end

fprintf('\n');

%% --- STEP 3: PLOTS (SIDE BY SIDE) ---

figure('Name', 'Production Error Comparison', 'Color', 'w', 'Position', [100 100 1400 500]);

% --- LEFT PLOT: GROUPED ---
subplot(1,2,1);
hold on;

valid_grp = ~isnan(prod_mean_t_grp) & ~isnan(prod_mean_h_grp);
x_grp = find(valid_grp);
grp_labels = {'60°/300°->120°', '120°/240°->60°'};
grp_labels_plot = grp_labels(valid_grp);

b1 = bar(x_grp - 0.2, prod_mean_t_grp(valid_grp), 0.35, 'FaceColor', [0.2 0.4 0.8], 'EdgeColor', 'none');
b2 = bar(x_grp + 0.2, prod_mean_h_grp(valid_grp), 0.35, 'FaceColor', [0.8 0.2 0.2], 'EdgeColor', 'none');

errorbar(x_grp - 0.2, prod_mean_t_grp(valid_grp), prod_sd_t_grp(valid_grp), 'k.', 'LineWidth', 1.2, 'CapSize', 6);
errorbar(x_grp + 0.2, prod_mean_h_grp(valid_grp), prod_sd_h_grp(valid_grp), 'k.', 'LineWidth', 1.2, 'CapSize', 6);

set(gca, 'XTick', x_grp, 'XTickLabel', grp_labels_plot, 'FontSize', 12, 'Box', 'off');
ylabel('Absolute Error (°)', 'FontSize', 13);
title('Grouped Targets', 'FontSize', 14, 'FontWeight', 'bold');
legend([b1 b2], {'Torso', 'Head'}, 'Location', 'northwest', 'FontSize', 11);
ylim([0 max([prod_mean_t_grp(valid_grp) + prod_sd_t_grp(valid_grp); prod_mean_h_grp(valid_grp) + prod_sd_h_grp(valid_grp)]) * 1.2]);
hold off;

% --- RIGHT PLOT: INDIVIDUAL ---
subplot(1,2,2);
hold on;

prod_labels = {'60°->120°', '120°->60°', '240°->60°', '300°->120°'};
valid_ind = ~isnan(prod_mean_t) & ~isnan(prod_mean_h);
x_ind = find(valid_ind);
prod_labels_plot = prod_labels(valid_ind);

b3 = bar(x_ind - 0.2, prod_mean_t(valid_ind), 0.35, 'FaceColor', [0.2 0.4 0.8], 'EdgeColor', 'none');
b4 = bar(x_ind + 0.2, prod_mean_h(valid_ind), 0.35, 'FaceColor', [0.8 0.2 0.2], 'EdgeColor', 'none');

errorbar(x_ind - 0.2, prod_mean_t(valid_ind), prod_sd_t(valid_ind), 'k.', 'LineWidth', 1.2, 'CapSize', 6);
errorbar(x_ind + 0.2, prod_mean_h(valid_ind), prod_sd_h(valid_ind), 'k.', 'LineWidth', 1.2, 'CapSize', 6);

set(gca, 'XTick', x_ind, 'XTickLabel', prod_labels_plot, 'FontSize', 12, 'Box', 'off');
ylabel('Absolute Error (°)', 'FontSize', 13);
title('Individual Targets', 'FontSize', 14, 'FontWeight', 'bold');
legend([b3 b4], {'Torso', 'Head'}, 'Location', 'northwest', 'FontSize', 11);
ylim([0 max([prod_mean_t(valid_ind) + prod_sd_t(valid_ind); prod_mean_h(valid_ind) + prod_sd_h(valid_ind)]) * 1.2]);
hold off;
