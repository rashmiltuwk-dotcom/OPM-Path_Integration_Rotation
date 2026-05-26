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
    % Using abs(abs(...) - targetDeg) ensures overshoot/undershoot both count as error
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
% (Rest of your script remains identical, just referencing the new 'acc' variables)
is_phys = strcmp(modality, 'P');
E_et = enc_targ(~isnan(enc_acc_t));
P_et = enc_targ(is_phys & ~isnan(prod_acc_t));
P_rt = res_targ(is_phys & ~isnan(prod_acc_t));

% ... [Run your ANOVA/T-Test functions exactly as before using the acc vectors] ...

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
