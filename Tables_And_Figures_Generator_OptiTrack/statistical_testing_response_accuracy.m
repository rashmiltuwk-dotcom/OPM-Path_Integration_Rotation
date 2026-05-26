%% ============================================================
%  ROTATION ACCURACY — STATISTICAL COMPARISONS
%% ============================================================

%% --- STEP 1: LOAD & SPLIT BY MODALITY ----------------------
accepted = MasterData(strcmp({MasterData.Status}, 'Accepted'));
N = numel(accepted);
if N == 0, error('No accepted trials in MasterData.'); end

res_err  = NaN(N,1);   % response active error  (Physical only)
enc_err  = NaN(N,1);   % encoding active error  (all trials)
modality = cell(N,1);
enc_targ = NaN(N,1);   % encoding target: 60 / 120 / 240 / 300
res_targ = NaN(N,1);   % response target: 60 or 120

for i = 1:N
    tr = accepted(i);

    switch tr.TargetDeg
        case 60,  rTarget = 120;
        case 120, rTarget = 60;
        case 240, rTarget = 60;
        case 300, rTarget = 120;
        otherwise, rTarget = NaN;
    end

    enc_targ(i) = tr.TargetDeg;
    res_targ(i) = rTarget;
    modality{i} = tr.TaskType;

    % Encoding accuracy: all trials
    enc_err(i) = compute_active_error(tr.Traces.EncodingRotateTorsoTrace, tr.TargetDeg);

    % Response accuracy: Physical only
    if strcmp(tr.TaskType, 'P')
        res_err(i) = compute_active_error(tr.Traces.ResponseRotationTorsoTrace, rTarget);
    end
end

%% --- STEP 2: BUILD ANALYSIS VECTORS ------------------------
is_phys = strcmp(modality, 'P');
is_imag = strcmp(modality, 'I');

% Response: Physical trials only
R    = res_err(is_phys & ~isnan(res_err));
R_et = enc_targ(is_phys & ~isnan(res_err));
R_rt = res_targ(is_phys & ~isnan(res_err));

% Encoding: all trials
E_all   = enc_err(~isnan(enc_err));
E_phys  = enc_err(is_phys & ~isnan(enc_err));
E_imag  = enc_err(is_imag & ~isnan(enc_err));
ET_phys = enc_targ(is_phys & ~isnan(enc_err));
ET_imag = enc_targ(is_imag & ~isnan(enc_err));

%% --- STEP 3: DESCRIPTIVE OUTPUT ----------------------------
fprintf('\n============ ACCURACY STATISTICS ============\n');

% --- Response summary (Physical only)
fprintf('\n--- RESPONSE ACCURACY  [Physical trials only, N=%d] ---\n', numel(R));
fprintf('Overall:  Mean=%+.3f°  SD=%.3f°  AbsMean=%.3f°\n\n', mean(R), std(R), mean(abs(R)));
for q = [60, 120, 240, 300]
    v = R(R_et == q);
    if isempty(v), continue; end
    fprintf('Enc %3d°  N=%d  Mean=%+.3f°\n', q, numel(v), mean(v));
end
fprintf('Response target 60°:   N=%d  Mean=%+.3f°\n', sum(R_rt==60), mean(R(R_rt==60)));
fprintf('Response target 120°:  N=%d  Mean=%+.3f°\n', sum(R_rt==120), mean(R(R_rt==120)));

% --- Encoding summary (all trials)
fprintf('\n--- ENCODING ACCURACY  [All trials, N=%d] ---\n', numel(E_all));
fprintf('Physical: Mean=%+.3f°  SD=%.3f°\nImagined: Mean=%+.3f°  SD=%.3f°\n\n', ...
    mean(E_phys), std(E_phys), mean(E_imag), std(E_imag));

%% --- STEP 4: STATISTICAL TESTS -----------------------------
fprintf('\n--- RESPONSE ACCURACY: One-Way ANOVA (Quadrants) ---\n');
[~, tbl_rq, stats_rq] = anova1(R, R_et, 'off');
print_anova1(tbl_rq);

fprintf('\n--- RESPONSE ACCURACY: t-test (60° vs 120° Response Targets) ---\n');
run_ttest2(R(R_rt==60), R(R_rt==120), '60° vs 120°');

fprintf('\n--- ENCODING ACCURACY: One-Way ANOVA (Quadrants) ---\n');
[~, tbl_eq, stats_eq] = anova1(E_all, enc_targ(~isnan(enc_err)), 'off');
print_anova1(tbl_eq);

fprintf('\n--- ENCODING ACCURACY: t-test (Physical vs Imagined) ---\n');
run_ttest2(E_phys, E_imag, 'Physical vs Imagined');

fprintf('\n');

%% --- LOCAL FUNCTIONS (Kept for compatibility) ---
function err = compute_active_error(activeTrace, targetDeg)
    if isempty(activeTrace) || ~isfield(activeTrace,'yaw') || numel(activeTrace.yaw) < 2
        err = NaN; return;
    end
    yaw = activeTrace.yaw(:);
    accumulated = 0;
    for j = 2:numel(yaw)
        delta = yaw(j) - yaw(j-1);
        if delta > 180, delta = delta - 360; end
        if delta < -180, delta = delta + 360; end
        accumulated = accumulated + delta;
    end
    err = abs(accumulated) - targetDeg;
end

function run_ttest2(a, b, label)
    a = a(~isnan(a)); b = b(~isnan(b));
    if numel(a) < 2 || numel(b) < 2
        fprintf('  %-26s  insufficient data\n', label); return;
    end
    [~, p, ~, stats] = ttest2(a, b);
    fprintf('  %-26s  t(%4.1f)=%+.3f  p=%.4f  %s\n', label, stats.df, stats.tstat, p, sig_stars(p));
end

function print_anova1(tbl)
    F = tbl{2,5}; p = tbl{2,6};
    fprintf('  F(%d,%d) = %.3f   p = %.4f   η²p = %.3f   %s\n', tbl{2,3}, tbl{3,3}, F, p, tbl{2,2}/(tbl{2,2}+tbl{3,2}), sig_stars(p));
end

function s = sig_stars(p)
    if p < 0.001, s = '***'; elseif p < 0.01, s = '**'; elseif p < 0.05, s = '*'; else, s = ''; end
end
