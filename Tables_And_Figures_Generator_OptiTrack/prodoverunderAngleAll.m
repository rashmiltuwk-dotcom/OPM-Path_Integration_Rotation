%% ============================================================
%  ACCURACY SUMMARY: MEAN & SD (DEGREES)
%  GROUPED: [60], [120], [240], [300]
%% ============================================================

%% --- STEP 1: DATA EXTRACTION ---
accepted = MasterData(strcmp({MasterData.Status}, 'Accepted'));
N = numel(accepted);
if N == 0, error('No accepted trials in MasterData.'); end

% Initialize storage
enc_err_t = NaN(N,1); enc_err_h = NaN(N,1);
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
        dispProdT = abs(mod(yProdT(end) - yProdT(1) + 180, 360) - 180);
        dispProdH = abs(mod(yProdH(end) - yProdH(1) + 180, 360) - 180);
        prod_err_t(i) = abs(mod(dispProdT - rTarget + 180, 360) - 180);
        prod_err_h(i) = abs(mod(dispProdH - rTarget + 180, 360) - 180);
    end
end

%% --- STEP 2: ENCODING SUMMARY (INDIVIDUAL TARGETS) ---
fprintf('\n--- ENCODING ERROR: MEAN ± SD (DEGREES) ---\n');
fprintf('%-15s | %-15s | %-15s\n', 'Group', 'Torso (°)', 'Head (°)');
fprintf('-----------------------------------------------------\n');

enc_targets_individual = [60, 120, 240, 300];
enc_mean_t = NaN(4,1); enc_sd_t = NaN(4,1);
enc_mean_h = NaN(4,1); enc_sd_h = NaN(4,1);

for i = 1:4
    idx = enc_targ == enc_targets_individual(i);
    t_vals = enc_err_t(idx);
    h_vals = enc_err_h(idx);
    enc_mean_t(i) = mean(t_vals); enc_sd_t(i) = std(t_vals);
    enc_mean_h(i) = mean(h_vals); enc_sd_h(i) = std(h_vals);
    fprintf('%-15s | %5.2f ± %4.2f | %5.2f ± %4.2f\n', ...
        sprintf('%d°', enc_targets_individual(i)), enc_mean_t(i), enc_sd_t(i), enc_mean_h(i), enc_sd_h(i));
end

%% --- STEP 3: PRODUCTION SUMMARY (MEAN ± SD) ---
fprintf('\n--- PRODUCTION ERROR: MEAN ± SD (DEGREES) ---\n');
fprintf('%-15s | %-15s | %-15s\n', 'Group', 'Torso (°)', 'Head (°)');
fprintf('-----------------------------------------------------\n');

is_phys = strcmp(modality, 'P');

prod_targets = [60, 120, 240, 300];
prod_responses = [120, 60, 60, 120];  % Corresponding response targets
prod_mean_t = NaN(4,1); prod_sd_t = NaN(4,1);
prod_mean_h = NaN(4,1); prod_sd_h = NaN(4,1);

for i = 1:4
    idx = enc_targ == prod_targets(i) & is_phys;
    t_p_vals = prod_err_t(idx);
    h_p_vals = prod_err_h(idx);
    prod_mean_t(i) = mean(t_p_vals); prod_sd_t(i) = std(t_p_vals);
    prod_mean_h(i) = mean(h_p_vals); prod_sd_h(i) = std(h_p_vals);
    fprintf('%-15s | %5.2f ± %4.2f | %5.2f ± %4.2f\n', ...
        sprintf('%d° → %d°', prod_targets(i), prod_responses(i)), prod_mean_t(i), prod_sd_t(i), prod_mean_h(i), prod_sd_h(i));
end

fprintf('\n');

%% --- STEP 4: PLOTS ---

enc_labels  = {'60°', '120°', '240°', '300°'};
prod_labels = {'60°->120°', '120°->60°', '240°->60°', '300°->120°'};
x_enc  = 1:4;
x_prod = 1:4;


% --- FIGURE 2: PRODUCTION ERROR ---
figure('Name', 'Production Error', 'Color', 'w', 'Position', [820 100 700 450]);
hold on;

valid_prod = ~isnan(prod_mean_t) & ~isnan(prod_mean_h);
x_prod_plot = find(valid_prod);
prod_labels_plot = prod_labels(valid_prod);

b3 = bar(x_prod_plot - 0.2, prod_mean_t(valid_prod), 0.35, 'FaceColor', [0.2 0.4 0.8], 'EdgeColor', 'none');
b4 = bar(x_prod_plot + 0.2, prod_mean_h(valid_prod), 0.35, 'FaceColor', [0.8 0.2 0.2], 'EdgeColor', 'none');

errorbar(x_prod_plot - 0.2, prod_mean_t(valid_prod), prod_sd_t(valid_prod), 'k.', 'LineWidth', 1.2, 'CapSize', 6);
errorbar(x_prod_plot + 0.2, prod_mean_h(valid_prod), prod_sd_h(valid_prod), 'k.', 'LineWidth', 1.2, 'CapSize', 6);

set(gca, 'XTick', x_prod_plot, 'XTickLabel', prod_labels_plot, 'FontSize', 12, 'Box', 'off');
ylabel('Absolute Error (°)', 'FontSize', 13);
xlabel('Encoding Target → Response Target', 'FontSize', 13);
title('Production Error by Target', 'FontSize', 14, 'FontWeight', 'bold');
legend([b3 b4], {'Torso', 'Head'}, 'Location', 'northwest', 'FontSize', 11);
ylim([0 max([prod_mean_t(valid_prod) + prod_sd_t(valid_prod); prod_mean_h(valid_prod) + prod_sd_h(valid_prod)]) * 1.2]);
hold off;
