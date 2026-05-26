%% ============================================================
%  COMPLETE ANALYSIS: ANOVA, POST-HOC, AND T-TESTS (TORSO & HEAD)
%% ============================================================

%% --- STEP 1: LOAD & CALCULATE ERRORS ---
accepted = MasterData(strcmp({MasterData.Status}, 'Accepted'));
N = numel(accepted);
if N == 0, error('No accepted trials in MasterData.'); end

% Initialize storage
enc_err_t = NaN(N,1); enc_err_h = NaN(N,1);
prod_err_t = NaN(N,1); prod_err_h = NaN(N,1);
modality = cell(N,1); enc_targ = NaN(N,1); res_targ = NaN(N,1);

for i = 1:N
    tr = accepted(i);
    modality{i} = tr.TaskType;
    enc_targ(i) = tr.TargetDeg;

    % Encoding: Absolute Error (Torso & Head)
    yEncT = tr.Traces.EncodingRotateTorsoTrace.yaw;
    yEncH = tr.Traces.EncodingRotateHeadTrace.yaw;
    enc_err_t(i) = abs(abs(mod(yEncT(end) - yEncT(1) + 180, 360) - 180) - tr.TargetDeg);
    enc_err_h(i) = abs(abs(mod(yEncH(end) - yEncH(1) + 180, 360) - 180) - tr.TargetDeg);

    % Production: Absolute Error (Torso & Head)
    if strcmp(tr.TaskType, 'P')
        if ismember(tr.TargetDeg, [60, 240]), rTarget = 120; else, rTarget = 60; end
        res_targ(i) = rTarget;
        yProdT = tr.Traces.ResponseRotationTorsoTrace.yaw;
        yProdH = tr.Traces.ResponseRotationHeadTrace.yaw;
        prod_err_t(i) = abs(abs(mod(yProdT(end) - yProdT(1) + 180, 360) - 180) - rTarget);
        prod_err_h(i) = abs(abs(mod(yProdH(end) - yProdH(1) + 180, 360) - 180) - rTarget);
    end
end

%% --- STEP 2: BUILD VECTORS ---
is_phys = strcmp(modality, 'P');
E_et = enc_targ(~isnan(enc_err_t));
P_et = enc_targ(is_phys & ~isnan(prod_err_t));
P_rt = res_targ(is_phys & ~isnan(prod_err_t));

%% --- STEP 3: ENCODING ANALYSIS ---
fprintf('\n--- ENCODING: TORSO ---\n');
run_anova_t(enc_err_t(~isnan(enc_err_t)), E_et, [60, 120, 240, 300]);
fprintf('\n--- ENCODING: HEAD ---\n');
run_anova_t(enc_err_h(~isnan(enc_err_h)), E_et, [60, 120, 240, 300]);

%% --- STEP 4: PRODUCTION ANALYSIS ---
fprintf('\n--- PRODUCTION: TORSO ---\n');
run_anova_t(prod_err_t(is_phys & ~isnan(prod_err_t)), P_et, [60, 120, 240, 300]);
fprintf('\n--- PRODUCTION: HEAD ---\n');
run_anova_t(prod_err_h(is_phys & ~isnan(prod_err_h)), P_et, [60, 120, 240, 300]);

% T-Tests for Response Targets
fprintf('\n--- T-TESTS: PRODUCTION (60 vs 120) ---\n');
run_ttest2(prod_err_t(P_rt==60), prod_err_t(P_rt==120), 'Torso: 60 vs 120');
run_ttest2(prod_err_h(P_rt==60), prod_err_h(P_rt==120), 'Head: 60 vs 120');

%% --- LOCAL FUNCTIONS ---
function run_anova_t(data, groups, list)
    [~, tbl, stats] = anova1(data, groups, 'off');
    print_anova1(tbl);
    if tbl{2,6} < 0.05
        [c,~,~,gn] = multcompare(stats, 'Display','off');
        print_multcomp(c, gn);
    end
    print_group_stats(data, groups, list);
end

function print_group_stats(data, groups, list)
    fprintf('  %-10s  %-6s  %-10s\n', 'Group', 'N', 'Mean ± SD');
    for g = list
        idx = (groups == g);
        fprintf('  %3d°        %d     %6.3f ± %6.3f\n', g, sum(idx), mean(data(idx)), std(data(idx)));
    end
end

function run_ttest2(a, b, label)
    a = a(~isnan(a)); b = b(~isnan(b));
    [~, p, ~, stats] = ttest2(a, b);
    fprintf('  %-26s t(%4.1f)=%+.3f p=%.4f %s\n', label, stats.df, stats.tstat, p, sig_stars(p));
end

function print_anova1(tbl)
    F = tbl{2,5}; p = tbl{2,6}; eta2p = tbl{2,2} / (tbl{2,2} + tbl{3,2});
    fprintf('  F(%d,%d) = %.3f    p = %.4f    η²p = %.3f\n', tbl{2,3}, tbl{3,3}, F, p, eta2p);
end

function print_multcomp(c, gn)
    for row = 1:size(c,1)
        if c(row,6) < 0.05
            fprintf('    %-6s vs %-6s  Diff=%+.3f°  p=%.4f  %s\n', ...
                gn{c(row,1)}, gn{c(row,2)}, c(row,4), c(row,6), sig_stars(c(row,6)));
        end
    end
end

function s = sig_stars(p)
    if p<0.001, s='***'; elseif p<0.01, s='**'; elseif p<0.05, s='*'; else, s=''; end
end
