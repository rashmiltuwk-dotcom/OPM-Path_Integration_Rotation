%% ============================================================
%  COMPLETE ANALYSIS: ANOVA, POST-HOC, AND T-TESTS (PERCENTAGE)
%% ============================================================
 
%% --- STEP 1: LOAD & CALCULATE ACCURACY (%) ---
accepted = MasterData(strcmp({MasterData.Status}, 'Accepted'));
N = numel(accepted);
if N == 0, error('No accepted trials in MasterData.'); end
 
% Initialize storage
enc_acc_t = NaN(N,1); enc_acc_h = NaN(N,1);
prod_acc_t = NaN(N,1); prod_acc_h = NaN(N,1);
modality = cell(N,1); enc_targ = NaN(N,1); res_targ = NaN(N,1);
 
for i = 1:N
    tr = accepted(i);
    modality{i} = tr.TaskType;
    enc_targ(i) = tr.TargetDeg;
 
    % Helper to compute accuracy (%)
    % Formula: (1 - (abs_error / target)) * 100
    calc_acc = @(yaw, target) max(0, (1 - (abs(abs(mod(yaw(end) - yaw(1) + 180, 360) - 180) - target) / target)) * 100);
 
    % Encoding: Accuracy (Torso & Head)
    enc_acc_t(i) = calc_acc(tr.Traces.EncodingRotateTorsoTrace.yaw, tr.TargetDeg);
    enc_acc_h(i) = calc_acc(tr.Traces.EncodingRotateHeadTrace.yaw, tr.TargetDeg);
 
    % Production: Accuracy (Torso & Head)
    if strcmp(tr.TaskType, 'P')
        if ismember(tr.TargetDeg, [60, 240]), rTarget = 120; else, rTarget = 60; end
        res_targ(i) = rTarget;
        prod_acc_t(i) = calc_acc(tr.Traces.ResponseRotationTorsoTrace.yaw, rTarget);
        prod_acc_h(i) = calc_acc(tr.Traces.ResponseRotationHeadTrace.yaw, rTarget);
    end
end
 
%% --- STEP 2: BUILD VECTORS & RUN ANALYSIS ---
is_phys = strcmp(modality, 'P');
is_imag = strcmp(modality, 'I');

fprintf('\n============================================================\n');
fprintf('                   ACCURACY ANALYSIS (%%)\n');
fprintf('============================================================\n\n');

%% --- ENCODING ACCURACY ---
fprintf('--- ENCODING ROTATION ---\n');
fprintf('Torso vs Head Accuracy\n');
run_ttest2(enc_acc_t, enc_acc_h, 'Encoding (All)');

fprintf('\nPhysical Only\n');
run_ttest2(enc_acc_t(is_phys), enc_acc_h(is_phys), 'Encoding (Physical)');

fprintf('\nImagined Only\n');
run_ttest2(enc_acc_t(is_imag), enc_acc_h(is_imag), 'Encoding (Imagined)');

%% --- PRODUCTION ACCURACY (PHYSICAL ONLY) ---
fprintf('\n--- PRODUCTION ROTATION (Physical Only) ---\n');
fprintf('Torso vs Head Accuracy\n');
run_ttest2(prod_acc_t(is_phys), prod_acc_h(is_phys), 'Production (All)');

%% --- BY TARGET ANGLE ---
fprintf('\n--- BY TARGET ANGLE ---\n');
targets = unique(enc_targ);
targets(isnan(targets)) = [];

for t = targets'
    mask = enc_targ == t;
    t_data = enc_acc_t(mask); t_data = t_data(~isnan(t_data));
    h_data = enc_acc_h(mask); h_data = h_data(~isnan(h_data));
    fprintf('\nTarget: %d°\n', t);
    fprintf('  Encoding: Torso=%.1f±%.1f%%  Head=%.1f±%.1f%%\n', ...
        mean(t_data), std(t_data), ...
        mean(h_data), std(h_data));
    run_ttest2(enc_acc_t(mask), enc_acc_h(mask), sprintf('  Ttest Target %d°', t));
end

%% --- MODALITY COMPARISON ---
fprintf('\n--- MODALITY COMPARISON ---\n');
fprintf('Physical vs Imagined (Encoding Torso)\n');
run_ttest2(enc_acc_t(is_phys), enc_acc_t(is_imag), 'Physical vs Imagined');

%% --- DESCRIPTIVE STATS TABLE ---
fprintf('\n============================================================\n');
fprintf('                   DESCRIPTIVE STATISTICS\n');
fprintf('============================================================\n\n');
fprintf('%-30s  %6s  %8s  %8s\n', 'Measure', 'N', 'Mean (%)', 'SD');
fprintf('%-30s  %6d  %8.1f  %8.1f\n', 'Encoding Torso (All)', numel(enc_acc_t(~isnan(enc_acc_t))), mean(enc_acc_t(~isnan(enc_acc_t))), std(enc_acc_t(~isnan(enc_acc_t))));
fprintf('%-30s  %6d  %8.1f  %8.1f\n', 'Encoding Head (All)', numel(enc_acc_h(~isnan(enc_acc_h))), mean(enc_acc_h(~isnan(enc_acc_h))), std(enc_acc_h(~isnan(enc_acc_h))));
fprintf('%-30s  %6d  %8.1f  %8.1f\n', 'Production Torso (Phys)', numel(prod_acc_t(is_phys & ~isnan(prod_acc_t))), mean(prod_acc_t(is_phys & ~isnan(prod_acc_t))), std(prod_acc_t(is_phys & ~isnan(prod_acc_t))));
fprintf('%-30s  %6d  %8.1f  %8.1f\n', 'Production Head (Phys)', numel(prod_acc_h(is_phys & ~isnan(prod_acc_h))), mean(prod_acc_h(is_phys & ~isnan(prod_acc_h))), std(prod_acc_h(is_phys & ~isnan(prod_acc_h))));
fprintf('\n');

%% --- LOCAL HELPER FUNCTIONS ---
function run_ttest2(a, b, label)
    a = a(~isnan(a)); b = b(~isnan(b));
    if numel(a) < 2 || numel(b) < 2
        fprintf('  %-40s  insufficient data\n', label); return;
    end
    [~, p, ~, stats] = ttest2(a, b);
    fprintf('  %-40s  t(%4.1f)=%+.3f  p=%.4f  %s\n', label, stats.df, stats.tstat, p, sig_stars(p));
end
 
function s = sig_stars(p)
    if p < 0.001, s = '***'; elseif p < 0.01, s = '**'; elseif p < 0.05, s = '*'; else, s = '(ns)'; end
end
