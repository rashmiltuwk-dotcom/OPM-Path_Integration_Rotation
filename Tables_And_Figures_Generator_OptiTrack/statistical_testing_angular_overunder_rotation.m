%% ============================================================
%  ROTATION ACCURACY — STATISTICAL COMPARISONS
%
%  RESPONSE accuracy: Physical trials only.
%  Imagined trials have no physical response rotation — torso
%  trace carries no accuracy signal for that phase.
%
%  ENCODING accuracy: All trials (encoding is always physical).
%
%  Key factor: Quadrant (60, 120, 240, 300 deg encoding target)
%% ============================================================

%% --- STEP 1: LOAD & SPLIT BY MODALITY ----------------------
accepted = MasterData(strcmp({MasterData.Status}, 'Accepted'));
N = numel(accepted);
if N == 0, error('No accepted trials in MasterData.'); end

res_err  = NaN(N,1);   % response active error  (Physical only)
enc_err  = NaN(N,1);   % encoding active error  (all trials)
modality = cell(N,1);
direction = cell(N,1);
enc_targ  = NaN(N,1);  % encoding target: 60 / 120 / 240 / 300
res_targ  = NaN(N,1);  % response target: 60 or 120

for i = 1:N
    tr = accepted(i);

    switch tr.TargetDeg
        case 60,  rTarget = 120;
        case 120, rTarget = 60;
        case 240, rTarget = 60;
        case 300, rTarget = 120;
        otherwise, rTarget = NaN;
    end

    enc_targ(i)  = tr.TargetDeg;
    res_targ(i)  = rTarget;
    modality{i}  = tr.TaskType;
    direction{i} = tr.Direction;

    % Encoding accuracy: all trials
    enc_err(i) = compute_active_error( ...
        tr.Traces.EncodingRotateTorsoTrace, tr.TargetDeg);

    % Response accuracy: Physical only
    if strcmp(tr.TaskType, 'P')
        res_err(i) = compute_active_error( ...
            tr.Traces.ResponseRotationTorsoTrace, rTarget);
    end
    % Imagined stays NaN — no physical movement to measure
end

%% --- STEP 2: BUILD ANALYSIS VECTORS ------------------------
is_phys = strcmp(modality, 'P');
is_imag = strcmp(modality, 'I');

% Response: Physical trials only
R     = res_err(is_phys & ~isnan(res_err));
R_dir = direction(is_phys & ~isnan(res_err));
R_et  = enc_targ(is_phys & ~isnan(res_err));
R_rt  = res_targ(is_phys & ~isnan(res_err));

% Encoding: all trials, then split
E_all  = enc_err(~isnan(enc_err));
E_mod  = modality(~isnan(enc_err));
E_dir  = direction(~isnan(enc_err));
E_et   = enc_targ(~isnan(enc_err));

E_phys = enc_err(is_phys & ~isnan(enc_err));
E_imag = enc_err(is_imag & ~isnan(enc_err));
ET_phys = enc_targ(is_phys & ~isnan(enc_err));
ET_imag = enc_targ(is_imag & ~isnan(enc_err));

%% --- STEP 3: DESCRIPTIVE OUTPUT ----------------------------
fprintf('\n============ ACCURACY STATISTICS ============\n');

% --- Response summary (Physical only)
fprintf('\n--- RESPONSE ACCURACY  [Physical trials only, N=%d] ---\n', numel(R));
fprintf('Overall:  Mean=%+.3f°  SD=%.3f°  AbsMean=%.3f°\n\n', ...
    mean(R), std(R), mean(abs(R)));
fprintf('%-10s  %6s  %8s  %7s  %8s\n', 'Quadrant', 'N', 'Mean°', 'SD°', 'AbsMean°');
fprintf('%s\n', repmat('-',1,46));
for q = [60, 120, 240, 300]
    v = R(R_et == q);
    if isempty(v), continue; end
    fprintf('Enc %3d°  %6d  %+8.3f  %7.3f  %8.3f\n', ...
        q, numel(v), mean(v), std(v), mean(abs(v)));
end
fprintf('\nResponse target 60°:   N=%d  Mean=%+.3f°  SD=%.3f°\n', ...
    sum(R_rt==60),  mean(R(R_rt==60)),  std(R(R_rt==60)));
fprintf('Response target 120°:  N=%d  Mean=%+.3f°  SD=%.3f°\n', ...
    sum(R_rt==120), mean(R(R_rt==120)), std(R(R_rt==120)));

% --- Encoding summary (all trials)
fprintf('\n--- ENCODING ACCURACY  [All trials, N=%d] ---\n', numel(E_all));
fprintf('Physical:  Mean=%+.3f°  SD=%.3f°\n', mean(E_phys), std(E_phys));
fprintf('Imagined:  Mean=%+.3f°  SD=%.3f°\n', mean(E_imag), std(E_imag));
fprintf('\n%-10s  %6s  %8s  %7s  %8s  %8s\n', ...
    'Quadrant', 'N', 'P Mean°', 'I Mean°', 'P SD°', 'I SD°');
fprintf('%s\n', repmat('-',1,56));
for q = [60, 120, 240, 300]
    vP = E_phys(ET_phys == q);
    vI = E_imag(ET_imag == q);
    fprintf('Enc %3d°  %6d  %+8.3f  %+8.3f  %7.3f  %7.3f\n', ...
        q, numel(vP)+numel(vI), ...
        safe_mean(vP), safe_mean(vI), ...
        safe_std(vP),  safe_std(vI));
end

%% --- STEP 4: STATISTICAL TESTS -----------------------------
fprintf('\n\n--- RESPONSE ACCURACY: ONE-WAY ANOVA across Quadrants ---\n');
fprintf('(Physical trials only — N=%d)\n', numel(R));
[~, tbl_rq, stats_rq] = anova1(R, R_et, 'off');
print_anova1(tbl_rq);
if tbl_rq{2,6} < 0.05
    fprintf('  Post-hoc (Tukey-Kramer):\n');
    [c,~,~,gn] = multcompare(stats_rq, 'Display','off');
    print_multcomp(c, gn);
end

fprintf('\n--- RESPONSE ACCURACY: t-test  Left vs Right ---\n');
run_ttest2(R(strcmp(R_dir,'L')), R(strcmp(R_dir,'R')), 'Left vs Right');

fprintf('\n--- RESPONSE ACCURACY: t-test  RespTarget 60° vs 120° ---\n');
run_ttest2(R(R_rt==60), R(R_rt==120), '60° vs 120°');

fprintf('\n--- ENCODING ACCURACY: ONE-WAY ANOVA across Quadrants ---\n');
fprintf('(All trials — N=%d)\n', numel(E_all));
[~, tbl_eq, stats_eq] = anova1(E_all, E_et, 'off');
print_anova1(tbl_eq);
if tbl_eq{2,6} < 0.05
    fprintf('  Post-hoc (Tukey-Kramer):\n');
    [c,~,~,gn] = multcompare(stats_eq, 'Display','off');
    print_multcomp(c, gn);
end

fprintf('\n--- ENCODING ACCURACY: t-test  Physical vs Imagined ---\n');
run_ttest2(E_phys, E_imag, 'Physical vs Imagined');

fprintf('\n--- ENCODING ACCURACY: t-test  Left vs Right ---\n');
E_dir_all = E_dir(~isnan(E_all));  % already stripped above
run_ttest2(E_all(strcmp(E_dir,'L')), E_all(strcmp(E_dir,'R')), 'Left vs Right');

fprintf('\n');

%% ============================================================
%  LOCAL FUNCTIONS
%% ============================================================

function err = compute_active_error(activeTrace, targetDeg)
    if isempty(activeTrace) || ~isfield(activeTrace,'yaw') || numel(activeTrace.yaw) < 2
        err = NaN; return;
    end
    yaw = activeTrace.yaw(:);
    accumulated = 0;
    for j = 2:numel(yaw)
        delta = yaw(j) - yaw(j-1);
        if delta >  180, delta = delta - 360; end
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
    fprintf('  %-26s  t(%4.1f)=%+.3f  p=%.4f  %s\n', ...
        label, stats.df, stats.tstat, p, sig_stars(p));
end

function print_anova1(tbl)
    % anova1 table: Source | SS | df | MS | F | Prob>F
    F   = tbl{2,5}; p = tbl{2,6};
    df1 = tbl{2,3}; df2 = tbl{3,3};
    SS_eff = tbl{2,2}; SS_err = tbl{3,2};
    eta2p  = SS_eff / (SS_eff + SS_err);
    fprintf('  F(%d,%d) = %.3f   p = %.4f   η²p = %.3f   %s\n', ...
        df1, df2, F, p, eta2p, sig_stars(p));
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

function v = safe_mean(x)
    x = x(~isnan(x));
    if isempty(x), v = NaN; else, v = mean(x); end
end

function v = safe_std(x)
    x = x(~isnan(x));
    if isempty(x), v = NaN; else, v = std(x); end
end

function s = sig_stars(p)
    if     p < 0.001, s = '***';
    elseif p < 0.01,  s = '**';
    elseif p < 0.05,  s = '*';
    else,             s = '';
    end
end
