%% ============================================================
%  ACCURACY SUMMARY: MEAN & SD (PERCENTAGE OF TARGET)
%  GROUPED: [60/120] AND [240/300]
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

    % Encoding Absolute Errors
    yEncT = tr.Traces.EncodingRotateTorsoTrace.yaw;
    yEncH = tr.Traces.EncodingRotateHeadTrace.yaw;
    enc_err_t(i) = abs(abs(mod(yEncT(end) - yEncT(1) + 180, 360) - 180) - tr.TargetDeg);
    enc_err_h(i) = abs(abs(mod(yEncH(end) - yEncH(1) + 180, 360) - 180) - tr.TargetDeg);

    % Production Absolute Errors
    if strcmp(tr.TaskType, 'P')
        if ismember(tr.TargetDeg, [60, 240]), rTarget = 120; else, rTarget = 60; end
        yProdT = tr.Traces.ResponseRotationTorsoTrace.yaw;
        yProdH = tr.Traces.ResponseRotationHeadTrace.yaw;
        prod_err_t(i) = abs(abs(mod(yProdT(end) - yProdT(1) + 180, 360) - 180) - rTarget);
        prod_err_h(i) = abs(abs(mod(yProdH(end) - yProdH(1) + 180, 360) - 180) - rTarget);
    end
end

%% --- STEP 2: GROUPED PERCENTAGE SUMMARY ---
fprintf('\n--- ENCODING ACCURACY: MEAN ± SD (%% OF TARGET) ---\n');
fprintf('%-15s | %-15s | %-15s\n', 'Group', 'Torso %', 'Head %');
fprintf('-----------------------------------------------------\n');

groups = {[60, 120], [240, 300]};
group_names = {'60°/120°', '240°/300°'};

for i = 1:2
    idx = ismember(enc_targ, groups{i});
    
    % Mean percentage error: Average individual errors normalized by their targets
    t_vals = enc_err_t(idx) ./ enc_targ(idx) * 100;
    h_vals = enc_err_h(idx) ./ enc_targ(idx) * 100;
    
    fprintf('%-15s | %5.2f ± %4.2f | %5.2f ± %4.2f\n', ...
        group_names{i}, mean(t_vals), std(t_vals), mean(h_vals), std(h_vals));
end

%% --- STEP 3: PRODUCTION SUMMARY (MEAN ± SD) ---
fprintf('\n--- PRODUCTION ACCURACY: MEAN ± SD (%% OF TARGET) ---\n');
fprintf('%-15s | %-15s | %-15s\n', 'Group', 'Torso %', 'Head %');
fprintf('-----------------------------------------------------\n');

is_phys = strcmp(modality, 'P');

for i = 1:2
    % Map encoding targets to production response targets
    idx = ismember(enc_targ, groups{i}) & is_phys;
    
    % Determine the response target for these specific trials
    % 60/120 encoding groups map to specific response targets
    rt = zeros(size(enc_targ));
    rt(ismember(enc_targ, [60, 240])) = 120;
    rt(ismember(enc_targ, [120, 300])) = 60;
    
    % Calculate normalized percentages
    t_p_vals = prod_err_t(idx) ./ rt(idx) * 100;
    h_p_vals = prod_err_h(idx) ./ rt(idx) * 100;
    
    % Print Mean ± SD
    fprintf('Prod %-10s | %5.2f ± %4.2f | %5.2f ± %4.2f\n', ...
        group_names{i}, mean(t_p_vals), std(t_p_vals), mean(h_p_vals), std(h_p_vals));
end
