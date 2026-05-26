%% ============================================================
%  COMPLETE ANALYSIS SCRIPT: ROTATION ABSOLUTE ERROR
%  Includes: Mean/SD/Post-Hoc/Anova/T-Test
%% ============================================================

%% --- STEP 1: LOAD & CALCULATE ERRORS ---
accepted = MasterData(strcmp({MasterData.Status}, 'Accepted'));
N = numel(accepted);
if N == 0, error('No accepted trials in MasterData.'); end

enc_err  = NaN(N,1);
prod_err = NaN(N,1);
modality = cell(N,1);
enc_targ = NaN(N,1);

for i = 1:N
    tr = accepted(i);
    modality{i} = tr.TaskType;
    enc_targ(i) = tr.TargetDeg;

    % 1. ENCODING: Absolute Error
    yawEnc  = tr.Traces.EncodingRotateTorsoTrace.yaw;
    rawEnc  = mod(yawEnc(end) - yawEnc(1) + 180, 360) - 180;
    enc_err(i) = abs(abs(rawEnc) - tr.TargetDeg);

    % 2. PRODUCTION: Absolute Error (Physical only)
    if strcmp(tr.TaskType, 'P')
        yawProd = tr.Traces.ResponseRotationTorsoTrace.yaw;
        rawProd = mod(yawProd(end) - yawProd(1) + 180, 360) - 180;
        
        if ismember(tr.TargetDeg, [60, 240]), rTarget = 120;
        else, rTarget = 60; end
        
        prod_err(i) = abs(abs(rawProd) - rTarget);
    end
end

%% --- STEP 2: BUILD VECTORS ---
is_phys = strcmp(modality, 'P');
is_imag = strcmp(modality, 'I');

P_err   = prod_err(is_phys & ~isnan(prod_err));
P_et    = enc_targ(is_phys & ~isnan(prod_err));
E_phys  = enc_err(is_phys & ~isnan(enc_err));
E_imag  = enc_err(is_imag & ~isnan(enc_err));

%% --- STEP 3: OUTPUT ---
fprintf('\n============ ABSOLUTE ERROR STATISTICS ============\n');
fprintf('Production Mean: %8.3f° (SD=%.3f°)\n', mean(P_err), std(P_err));
fprintf('Encoding Physical: %8.3f° (SD=%.3f°) | Imagined: %8.3f° (SD=%.3f°)\n', ...
    mean(E_phys), std(E_phys), mean(E_imag), std(E_imag));

fprintf('\n--- ANOVA: Production Accuracy by Quadrant ---\n');
[~, tbl_rq, stats_rq] = anova1(P_err, P_et, 'off');
print_anova1(tbl_rq);
if tbl_rq{2,6} < 0.05
    [c,~,~,gn] = multcompare(stats_rq, 'Display','off');
    print_multcomp(c, gn);
end

fprintf('\n--- T-TEST: Physical vs Imagined Encoding ---\n');
run_ttest2(E_phys, E_imag, 'Phys vs Imag');

%% --- LOCAL FUNCTIONS ---
function run_ttest2(a, b, label)
    a = a(~isnan(a)); b = b(~isnan(b));
    [~, p, ~, stats] = ttest2(a, b);
    fprintf('  %-26s t(%4.1f)=%+.3f p=%.4f %s\n', label, stats.df, stats.tstat, p, sig_stars(p));
end

function print_anova1(tbl)
    F = tbl{2,5}; p = tbl{2,6}; 
    eta2p = tbl{2,2} / (tbl{2,2} + tbl{3,2});
    fprintf('  F(%d,%d) = %.3f   p = %.4f   η²p = %.3f\n', tbl{2,3}, tbl{3,3}, F, p, eta2p);
end

function print_multcomp(c, gn)
    for row = 1:size(c,1)
        p = c(row,6);
        if p < 0.05
            fprintf('    %-6s vs %-6s  Diff=%+.3f°  p=%.4f  %s\n', ...
                gn{c(row,1)}, gn{c(row,2)}, c(row,4), p, sig_stars(p));
        end
    end
end

function s = sig_stars(p)
    if p<0.001, s='***'; elseif p<0.01, s='**'; elseif p<0.05, s='*'; else, s=''; end
end
