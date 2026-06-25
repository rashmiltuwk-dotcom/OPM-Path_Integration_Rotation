%% ============================================================
%  ACCURACY SUMMARY: FINAL ENCODING ERROR
%  ACTIVE ENCODING + PASSIVE ENCODING
%  MEAN & SD (DEGREES)
%  TARGET ANGLES: [60, 120, 240, 300]
%% ============================================================

%% --- STEP 1: DATA EXTRACTION ---
accepted = MasterData(strcmp({MasterData.Status}, 'Accepted'));
N = numel(accepted);
if N == 0, error('No accepted trials in MasterData.'); end

% Initialize storage
final_err_t = NaN(N,1); final_err_h = NaN(N,1);
modality = cell(N,1); enc_targ = NaN(N,1);

for i = 1:N
    tr = accepted(i);
    modality{i} = tr.TaskType;
    enc_targ(i) = tr.TargetDeg;
    
    % Active Encoding Rotation
    yEncT = tr.Traces.EncodingRotateTorsoTrace.yaw;
    yEncH = tr.Traces.EncodingRotateHeadTrace.yaw;
    
    rawDispT = mod(yEncT(end) - yEncT(1) + 180, 360) - 180;
    rawDispH = mod(yEncH(end) - yEncH(1) + 180, 360) - 180;
    
    if strcmp(tr.Direction, 'L')
        dispT = mod(rawDispT + 360, 360);
        dispH = mod(rawDispH + 360, 360);
    else
        dispT = mod(-rawDispT + 360, 360);
        dispH = mod(-rawDispH + 360, 360);
    end
    
    % Passive Encoding Rotation (additional degrees)
    yPassT = tr.Traces.PassiveEncodeTorsoTrace.yaw;
    yPassH = tr.Traces.PassiveEncodeHeadTrace.yaw;
    
    rawPassT = mod(yPassT(end) - yPassT(1) + 180, 360) - 180;
    rawPassH = mod(yPassH(end) - yPassH(1) + 180, 360) - 180;
    
    if strcmp(tr.Direction, 'L')
        passT = mod(rawPassT + 360, 360);
        passH = mod(rawPassH + 360, 360);
    else
        passT = mod(-rawPassT + 360, 360);
        passH = mod(-rawPassH + 360, 360);
    end
    
    % Combined displacement: Active + Passive
    totalDispT = dispT + passT;
    totalDispH = dispH + passH;
    
    % Final error: combined displacement vs target
    final_err_t(i) = abs(mod(totalDispT - tr.TargetDeg + 180, 360) - 180);
    final_err_h(i) = abs(mod(totalDispH - tr.TargetDeg + 180, 360) - 180);
    
end

%% --- STEP 2: FINAL ENCODING SUMMARY (INDIVIDUAL TARGETS) ---
fprintf('\n--- FINAL ENCODING ERROR (ACTIVE + PASSIVE): MEAN ± SD (DEGREES) ---\n');
fprintf('%-15s | %-15s | %-15s\n', 'Target', 'Torso (°)', 'Head (°)');
fprintf('-----------------------------------------------------\n');

enc_targets_individual = [60, 120, 240, 300];
final_mean_t = NaN(4,1); final_sd_t = NaN(4,1);
final_mean_h = NaN(4,1); final_sd_h = NaN(4,1);

for i = 1:4
    idx = enc_targ == enc_targets_individual(i);
    t_vals = final_err_t(idx);
    h_vals = final_err_h(idx);
    final_mean_t(i) = mean(t_vals); final_sd_t(i) = std(t_vals);
    final_mean_h(i) = mean(h_vals); final_sd_h(i) = std(h_vals);
    fprintf('%-15s | %5.2f ± %4.2f | %5.2f ± %4.2f\n', ...
        sprintf('%d°', enc_targets_individual(i)), final_mean_t(i), final_sd_t(i), final_mean_h(i), final_sd_h(i));
end

%% --- STEP 3: FINAL ENCODING ERROR PLOT ---

enc_labels = {'60°', '120°', '240°', '300°'};
x_enc = 1:4;

figure('Name', 'Final Encoding Error', 'Color', 'w', 'Position', [100 100 700 450]);
hold on;

b1 = bar(x_enc - 0.2, final_mean_t, 0.35, 'FaceColor', [0.2 0.4 0.8], 'EdgeColor', 'none'); % Blue - Torso
b2 = bar(x_enc + 0.2, final_mean_h, 0.35, 'FaceColor', [0.8 0.2 0.2], 'EdgeColor', 'none'); % Red - Head

errorbar(x_enc - 0.2, final_mean_t, final_sd_t, 'k.', 'LineWidth', 1.5, 'CapSize', 8, 'MarkerSize', 0.1);
errorbar(x_enc + 0.2, final_mean_h, final_sd_h, 'k.', 'LineWidth', 1.5, 'CapSize', 8, 'MarkerSize', 0.1);

set(gca, 'XTick', x_enc, 'XTickLabel', enc_labels, 'FontSize', 12, 'Box', 'off');
ylabel('Absolute Error (°)', 'FontSize', 13);
xlabel('Target Angle', 'FontSize', 13);
title('Final Encoding Error (Active + Passive)', 'FontSize', 14, 'FontWeight', 'bold');
legend([b1 b2], {'Torso', 'Head'}, 'Location', 'northwest', 'FontSize', 11);
ylim([0 max([final_mean_t + final_sd_t; final_mean_h + final_sd_h]) * 1.2]);
hold off;
