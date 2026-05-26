%% ============================================================
%  COMPLETE ANALYSIS: ANOVA, POST-HOC, AND T-TESTS
%% ============================================================

%% --- STEP 1: LOAD & CALCULATE ERRORS ---
accepted = MasterData(strcmp({MasterData.Status}, 'Accepted'));
N = numel(accepted);
if N == 0, error('No accepted trials in MasterData.'); end

enc_err  = NaN(N,1);
prod_err = NaN(N,1);
modality = cell(N,1);
enc_targ = NaN(N,1);
res_targ = NaN(N,1);

for i = 1:N
    tr = accepted(i);
    modality{i} = tr.TaskType;
    enc_targ(i) = tr.TargetDeg;

    % Encoding: Absolute Error
    yawEnc  = tr.Traces.EncodingRotateTorsoTrace.yaw;
    rawEnc  = mod(yawEnc(end) - yawEnc(1) + 180, 360) - 180;
    enc_err(i) = abs(abs(rawEnc) - tr.TargetDeg);

    % Production: Absolute Error
    if strcmp(tr.TaskType, 'P')
        yawProd = tr.Traces.ResponseRotationTorsoTrace.yaw;
        rawProd = mod(yawProd(end) - yawProd(1) + 180, 360) - 180;
        if ismember(tr.TargetDeg, [60, 240]), rTarget = 120; else, rTarget = 60; end
        res_targ(i) = rTarget;
        prod_err(i) = abs(abs(rawProd) - rTarget);
    end
end

%% --- STEP 2: BUILD VECTORS ---
is_phys = strcmp(modality, 'P');
P_err   = prod_err(is_phys & ~isnan(prod_err));
P_et    = enc_targ(is_phys & ~isnan(prod_err));
P_rt    = res_targ(is_phys & ~isnan(prod_err));
E_err   = enc_err(~isnan(enc_err));
E_et    = enc_targ(~isnan(enc_err));

%% --- STEP 3: ENCODING ANALYSIS ---
fprintf('\n--- ENCODING: ANOVA (4 Quadrants) ---\n');
[~, tbl_ea, stats_ea] = anova1(E_err, E_et, 'off');
print_anova1(tbl_ea);
if tbl_ea{2,6} < 0.05
    [c,~,~,gn] = multcompare(stats_ea, 'Display','off');
    print_multcomp(c, gn);
end
print_group_stats(E_err, E_et, [60, 120, 240, 300]);

fprintf('\n--- ENCODING: T-TEST (60/120 vs 240/300) ---\n');
run_ttest2(E_err(ismember(E_et, [60, 120])), E_err(ismember(E_et, [240, 300])), '60/120 vs 240/300');

%% --- STEP 4: PRODUCTION ANALYSIS ---
fprintf('\n--- PRODUCTION: ANOVA (4 Quadrants) ---\n');
[~, tbl_pa, stats_pa] = anova1(P_err, P_et, 'off');
print_anova1(tbl_pa);
if tbl_pa{2,6} < 0.05
    [c,~,~,gn] = multcompare(stats_pa, 'Display','off');
    print_multcomp(c, gn);
end
print_group_stats(P_err, P_et, [60, 120, 240, 300]);

fprintf('\n--- PRODUCTION: T-TEST (60 vs 120 Response Target) ---\n');
run_ttest2(P_err(P_rt==60), P_err(P_rt==120), '60 vs 120');

%% --- LOCAL FUNCTIONS ---
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
    fprintf('  F(%d,%d) = %.3f   p = %.4f   η²p = %.3f\n', tbl{2,3}, tbl{3,3}, F, p, eta2p);
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
