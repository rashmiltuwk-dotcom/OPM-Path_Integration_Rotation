%% ============================================================
%  HEAD-TORSO DISSOCIATION ANALYSIS
%% ============================================================

%% --- FILTERS (set to 'All' to include everything) ----------
filterTrial    = 1 : 64;   % Enter a specific number (e.g., 15) or range (e.g., 15:20)
filterDir      = 'All';   % 'L'    | 'R'    | 'All'
filterQuadrant = 'All';   % 'Q1'   | 'Q2'   | 'Q3'   | 'Q4'   | 'All'
filterDist     = 'All';   % 'D1'   | 'D2'   | 'D3'   | 'D4'   | 'All'
filterType     = 'All';   % 'I'    | 'P'    | 'All'
filterPos      = 'All';   % 'LPos' | 'RPos' | 'All'

%% --- LOOKUP TABLES -----------------------------------------
quadrantMap = containers.Map({'Q1','Q2','Q3','Q4'}, [60, 120, 240, 300]);
distanceMap = containers.Map({'D1','D2','D3','D4'}, [1.0, 1.5, 2.0, 2.5]);

%% --- STEP 1: FILTERING -------------------------------------
accepted = MasterData(strcmp({MasterData.Status}, 'Accepted'));
targetDegFilter  = resolve_filter(filterQuadrant, quadrantMap);
targetDistFilter = resolve_filter(filterDist,     distanceMap);

mask = true(1, numel(accepted));
for i = 1:numel(accepted)
    a = accepted(i);
    if isnumeric(filterTrial)   && ~ismember(a.TrialNum, filterTrial), mask(i) = false; end
    if ~strcmp(filterDir,  'All') && ~strcmp(a.Direction, filterDir),  mask(i) = false; end
    if ~strcmp(filterType, 'All') && ~strcmp(a.TaskType,  filterType), mask(i) = false; end
    if ~strcmp(filterPos,  'All') && ~strcmp(a.Position,  filterPos),  mask(i) = false; end
    if ~isnan(targetDegFilter)  && a.TargetDeg  ~= targetDegFilter,   mask(i) = false; end
    if ~isnan(targetDistFilter) && a.TargetDist ~= targetDistFilter,  mask(i) = false; end
end

subset = accepted(mask);
N = numel(subset);
if N == 0, error('No trials match the selected filters.'); end

%% --- STEP 2: METRIC COMPUTATION ----------------------------
% Calculate head-torso dissociation for encoding and production phases

metrics = struct('TrialNum', {}, 'TaskType', {}, ...
    'Enc_HeadRot', {}, 'Enc_TorsoRot', {}, 'Enc_Dissoc', {}, ...
    'Prod_HeadRot', {}, 'Prod_TorsoRot', {}, 'Prod_Dissoc', {});

for i = 1:N
    tr = subset(i);
    metrics(i).TrialNum = tr.TrialNum;
    metrics(i).TaskType = tr.TaskType;
    
    % --- ENCODING PHASE ---
    yaw_head_enc = tr.Traces.EncodingRotateHeadTrace.yaw;
    yaw_torso_enc = tr.Traces.EncodingRotateTorsoTrace.yaw;
    
    head_rot_enc = yaw_head_enc(end) - yaw_head_enc(1);
    torso_rot_enc = yaw_torso_enc(end) - yaw_torso_enc(1);
    
    % Handle 360-degree wraparound
    head_rot_enc = mod(head_rot_enc + 180, 360) - 180;
    torso_rot_enc = mod(torso_rot_enc + 180, 360) - 180;
    
    metrics(i).Enc_HeadRot = head_rot_enc;
    metrics(i).Enc_TorsoRot = torso_rot_enc;
    metrics(i).Enc_Dissoc = abs(head_rot_enc - torso_rot_enc);
    
    % --- PRODUCTION PHASE (Physical only) ---
    if strcmp(tr.TaskType, 'P')
        yaw_head_prod = tr.Traces.ResponseRotationHeadTrace.yaw;
        yaw_torso_prod = tr.Traces.ResponseRotationTorsoTrace.yaw;
        
        head_rot_prod = yaw_head_prod(end) - yaw_head_prod(1);
        torso_rot_prod = yaw_torso_prod(end) - yaw_torso_prod(1);
        
        head_rot_prod = mod(head_rot_prod + 180, 360) - 180;
        torso_rot_prod = mod(torso_rot_prod + 180, 360) - 180;
        
        metrics(i).Prod_HeadRot = head_rot_prod;
        metrics(i).Prod_TorsoRot = torso_rot_prod;
        metrics(i).Prod_Dissoc = abs(head_rot_prod - torso_rot_prod);
    else
        metrics(i).Prod_HeadRot = NaN;
        metrics(i).Prod_TorsoRot = NaN;
        metrics(i).Prod_Dissoc = NaN;
    end
end

%% --- STEP 3: OUTPUT ----------------------------------------
fprintf('\n================ HEAD-TORSO DISSOCIATION RESULTS ================\n');
fprintf('N = %d trials\n---------------------------------------------------------------------------\n', N);

% Separate by modality
is_phys = strcmp({metrics.TaskType}, 'P');
is_imag = strcmp({metrics.TaskType}, 'I');

fprintf('\n%-50s  %6s  %6s  %6s  %6s  %6s\n', 'Metric', 'N', 'Mean', 'SD', 'Min', 'Max');
fprintf('%s\n', repmat('-', 1, 100));
print_row('ENCODING — Head Rotation (degrees)',          [metrics.Enc_HeadRot]);
print_row('ENCODING — Torso Rotation (degrees)',         [metrics.Enc_TorsoRot]);
print_row('ENCODING — Dissociation (degrees)',           [metrics.Enc_Dissoc]);
fprintf('\n');
print_row('ENCODING — Dissociation (Physical)',          [metrics(is_phys).Enc_Dissoc]);
print_row('ENCODING — Dissociation (Imagined)',          [metrics(is_imag).Enc_Dissoc]);
fprintf('\n');
print_row('PRODUCTION — Head Rotation (degrees)',        [metrics.Prod_HeadRot]);
print_row('PRODUCTION — Torso Rotation (degrees)',       [metrics.Prod_TorsoRot]);
print_row('PRODUCTION — Dissociation (degrees)',         [metrics.Prod_Dissoc]);

assignin('base', 'HeadTorsoTable', struct2table(metrics));

%% --- STEP 4: T-TESTS ----------------------------------------
fprintf('\n%s\n', repmat('=', 1, 100));
fprintf('T-TESTS: PHYSICAL vs IMAGINED MODALITY\n');
fprintf('%s\n', repmat('=', 1, 100));

dissoc_enc_phys = [metrics(is_phys).Enc_Dissoc];
dissoc_enc_imag = [metrics(is_imag).Enc_Dissoc];
dissoc_prod_phys = [metrics(is_phys).Prod_Dissoc];

fprintf('\n--- ENCODING DISSOCIATION (Physical vs Imagined) ---\n');
fprintf('Physical:  n=%d,  M=%.2f ± %.2f°,  range [%.2f, %.2f]\n', ...
    numel(dissoc_enc_phys), mean(dissoc_enc_phys), std(dissoc_enc_phys), ...
    min(dissoc_enc_phys), max(dissoc_enc_phys));
fprintf('Imagined:  n=%d,  M=%.2f ± %.2f°,  range [%.2f, %.2f]\n', ...
    numel(dissoc_enc_imag), mean(dissoc_enc_imag), std(dissoc_enc_imag), ...
    min(dissoc_enc_imag), max(dissoc_enc_imag));

% Run t-test if both groups have data
if numel(dissoc_enc_phys) > 0 && numel(dissoc_enc_imag) > 0
    try
        [t_enc, p_enc, df_enc] = ttest2_custom(dissoc_enc_phys, dissoc_enc_imag);
        fprintf('\n');
        fprintf('Mean Difference: %.2f°\n', mean(dissoc_enc_phys) - mean(dissoc_enc_imag));
        fprintf('t(%.1f) = %.3f, p = %.4f  %s\n', df_enc, t_enc, p_enc, sig_stars(p_enc));
        fprintf('Cohen''s d = %.3f\n', cohens_d(dissoc_enc_phys, dissoc_enc_imag));
    catch
        fprintf('\n(Insufficient sample size for valid t-test)\n');
    end
else
    fprintf('\n(No data to compare)\n');
end

fprintf('\n--- PRODUCTION vs ENCODING (Physical Only) ---\n');
dissoc_prod_clean = dissoc_prod_phys(~isnan(dissoc_prod_phys));
if numel(dissoc_prod_clean) > 0 && numel(dissoc_enc_phys) > 0
    try
        diff_pair = dissoc_prod_clean - dissoc_enc_phys(1:numel(dissoc_prod_clean));
        fprintf('Encoding:   n=%d,  M=%.2f ± %.2f°,  range [%.2f, %.2f]\n', ...
            numel(dissoc_enc_phys), mean(dissoc_enc_phys), std(dissoc_enc_phys), ...
            min(dissoc_enc_phys), max(dissoc_enc_phys));
        fprintf('Production: n=%d,  M=%.2f ± %.2f°,  range [%.2f, %.2f]\n', ...
            numel(dissoc_prod_clean), mean(dissoc_prod_clean), std(dissoc_prod_clean), ...
            min(dissoc_prod_clean), max(dissoc_prod_clean));
        
        [t_prod, p_prod, df_prod] = ttest_paired_custom(diff_pair);
        fprintf('\n');
        fprintf('Mean Difference: %.2f°\n', mean(dissoc_prod_clean) - mean(dissoc_enc_phys(1:numel(dissoc_prod_clean))));
        fprintf('t(%.1f) = %.3f, p = %.4f  %s\n', df_prod, t_prod, p_prod, sig_stars(p_prod));
    catch
        fprintf('(Insufficient sample size for valid t-test)\n');
    end
else
    fprintf('(No physical trials for production analysis)\n');
end

%% --- STEP 5: VISUALIZATION ----------
figure('Name', 'Head-Torso Dissociation', 'NumberTitle', 'off', 'Position', [100 100 1200 500]);
set(gcf, 'PaperPositionMode', 'auto');

% --- LEFT: Encoding Dissociation (Physical vs Imagined) ---
subplot(1, 2, 1);
hold on;
scatter(ones(numel(dissoc_enc_phys),1) + randn(numel(dissoc_enc_phys),1)*0.05, dissoc_enc_phys, 80, 'b', 'filled');
scatter(2*ones(numel(dissoc_enc_imag),1) + randn(numel(dissoc_enc_imag),1)*0.05, dissoc_enc_imag, 80, 'r', 'filled');
% Add mean lines
plot([0.7 1.3], [mean(dissoc_enc_phys) mean(dissoc_enc_phys)], 'b-', 'LineWidth', 3);
plot([1.7 2.3], [mean(dissoc_enc_imag) mean(dissoc_enc_imag)], 'r-', 'LineWidth', 3);
set(gca, 'XTick', [1 2], 'XTickLabel', {'Physical', 'Imagined'}, 'XLim', [0.5 2.5]);
ylabel('Dissociation (°)', 'FontSize', 12);
title('ENCODING: Head-Torso Dissociation', 'FontSize', 13, 'FontWeight', 'bold');
grid on;
hold off;

% --- RIGHT: Production vs Encoding (Physical Only) ---
subplot(1, 2, 2);
hold on;
scatter(ones(numel(dissoc_enc_phys),1) + randn(numel(dissoc_enc_phys),1)*0.05, dissoc_enc_phys, 80, 'b', 'filled');
if numel(dissoc_prod_phys(~isnan(dissoc_prod_phys))) > 0
    scatter(2*ones(numel(dissoc_prod_phys(~isnan(dissoc_prod_phys))),1) + randn(numel(dissoc_prod_phys(~isnan(dissoc_prod_phys))),1)*0.05, dissoc_prod_phys(~isnan(dissoc_prod_phys)), 80, 'g', 'filled');
    plot([1.7 2.3], [mean(dissoc_prod_phys, 'omitnan') mean(dissoc_prod_phys, 'omitnan')], 'g-', 'LineWidth', 3);
end
plot([0.7 1.3], [mean(dissoc_enc_phys) mean(dissoc_enc_phys)], 'b-', 'LineWidth', 3);
set(gca, 'XTick', [1 2], 'XTickLabel', {'Encoding', 'Production'}, 'XLim', [0.5 2.5]);
ylabel('Dissociation (°)', 'FontSize', 12);
title('PRODUCTION: Encoding vs Response Rotation', 'FontSize', 13, 'FontWeight', 'bold');
grid on;
hold off;

sgtitle('Head-Torso Dissociation Analysis', 'FontSize', 14, 'FontWeight', 'bold');

fprintf('\n%s\n', repmat('=', 1, 100));

%% ============================================================
%  LOCAL FUNCTIONS
%% ============================================================

function val = resolve_filter(code, map)
    if strcmp(code, 'All'), val = NaN; else, val = map(code); end
end

function print_row(label, vals)
    vals = vals(~isnan(vals));
    if isempty(vals), fprintf('%-50s  %6d  %6s  %6s  %6s  %6s\n', label, 0, '—', '—', '—', '—');
    else, fprintf('%-50s  %6d  %6.2f  %6.2f  %6.2f  %6.2f\n', label, numel(vals), mean(vals), std(vals), min(vals), max(vals)); end
end

function [t_stat, p_val, df] = ttest2_custom(x, y)
    % Independent samples t-test (no Statistics Toolbox required)
    n1 = numel(x);
    n2 = numel(y);
    df = n1 + n2 - 2;
    
    m1 = mean(x);
    m2 = mean(y);
    s1 = std(x);
    s2 = std(y);
    
    % Pooled standard error
    s_pooled = sqrt(((n1-1)*s1^2 + (n2-1)*s2^2) / df);
    se = s_pooled * sqrt(1/n1 + 1/n2);
    
    % t-statistic
    t_stat = (m1 - m2) / se;
    
    % p-value (two-tailed) using betainc instead of tcdf
    p_val = 2 * tcdf_approx(abs(t_stat), df);
end

function [t_stat, p_val, df] = ttest_paired_custom(diff)
    % Paired samples t-test (no Statistics Toolbox required)
    diff = diff(:);
    n = numel(diff);
    df = n - 1;
    
    m_diff = mean(diff);
    se_diff = std(diff) / sqrt(n);
    
    t_stat = m_diff / se_diff;
    
    % p-value (two-tailed) using betainc instead of tcdf
    p_val = 2 * tcdf_approx(abs(t_stat), df);
end

function p = tcdf_approx(t, df)
    % Approximate t-distribution CDF using incomplete beta function
    % Based on: tcdf(t, df) = 1 - 0.5*betainc(df/(df+t^2), df/2, 0.5)
    t = abs(t);
    p_upper = betainc(df/(df + t^2), df/2, 0.5) / 2;
    p = 1 - p_upper;  % Upper tail probability
end

function s = sig_stars(p)
    if p < 0.001, s = '***'; 
    elseif p < 0.01, s = '**'; 
    elseif p < 0.05, s = '*'; 
    elseif p < 0.10, s = '†'; 
    else, s = '(ns)'; 
    end
end

function d = cohens_d(group1, group2)
    n1 = numel(group1); 
    n2 = numel(group2);
    pooled_sd = sqrt(((n1-1)*std(group1)^2 + (n2-1)*std(group2)^2) / (n1 + n2 - 2));
    d = (mean(group1) - mean(group2)) / pooled_sd;
end
