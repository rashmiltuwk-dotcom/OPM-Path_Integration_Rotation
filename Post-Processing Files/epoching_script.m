%% HouseKeeping
clearvars
close all
pl=1;

% Change to your path format
addpath('/Users/rashmil/Documents/MATLAB')
spm('defaults','EEG')

cd('/Users/rashmil/Documents/MATLAB');


%% 1. Import Raw Data
disp('Importing raw LVM file...');

S_create = [];
S_create.data = 'log-run-003_array1.lvm';
D1 = spm_opm_create(S_create);


%% 2. Epoch & Baseline Step
disp('Running manual trigger detection, epoching, and baseline correction...');

% These fields mirror what spm_opm_epoch_trigger accepted as inputs.
% We define them explicitly here because we need access to them before
% SPM does — to run the bookend cleanup in step 2C.
S = [];
S.D = D1;
S.timewin = [-200 3000];      % [spm_opm_epoch_trigger] used this to build the trl matrix internally
S.bc = 1;
S.triggerChannels = {'T2', 'T3', 'T6', 'T7', 'T8', 'T9'};         % T10 excluded — backup master sync only
S.condLabels = {'Stim_T2', 'Stim_T3', 'Stim_T6', 'Stim_T7', 'Stim_T8', 'Stim_T9'};
S.thresh = 0.05;

% [spm_opm_epoch_trigger] internally called D.indchannel to resolve channel names to row indices
chan_idx  = D1.indchannel(S.triggerChannels);
trig_data = D1(chan_idx, :, 1);
fs        = D1.fsample;

% [spm_opm_epoch_trigger] internally detected rising edges using threshold crossings.
% We replicate that here so we can intercept the timeline before epoching.
all_events = []; % [sample_number, channel_id]

for c = 1:length(S.triggerChannels)
    is_high = trig_data(c, :) > S.thresh;              % [spm_opm_epoch_trigger] threshold crossing
    onsets  = find(diff(is_high) == 1) + 1;            % [spm_opm_epoch_trigger] rising edge detection
    for k = 1:length(onsets)
        all_events = [all_events; onsets(k), c];
    end
end

% Sort into a true chronological timeline
[~, sort_idx] = sort(all_events(:, 1));
all_events    = all_events(sort_idx, :);

% -------------------------------------------------------------------------
% 2C. CLEANUP — T2 BOOKEND METHOD
% spm_opm_epoch_trigger skipped straight from onset detection to epoching,
% making this intervention impossible. This entire block is new.
% -------------------------------------------------------------------------
valid_events = all_events;
ch1_id       = 1; % T2 = Close Eyes (block start) and Open Eyes (block end)

% Guard: odd number of T2 presses means the recording ended mid-block
ch1_indices = find(valid_events(:, 2) == ch1_id);

if mod(length(ch1_indices), 2) ~= 0
    valid_events(ch1_indices(end):end, :) = [];
    disp('WARNING: Dropped incomplete final block (odd number of T2 presses).');
end

% Recompute after the guard so indices reflect the trimmed valid_events
ch1_indices = find(valid_events(:, 2) == ch1_id);

% Loop backwards through T2 pairs — backwards prevents index corruption on deletion
for i = length(ch1_indices)-1 : -2 : 1
    start_idx    = ch1_indices(i);
    end_idx      = ch1_indices(i+1);
    block_events = valid_events(start_idx+1 : end_idx-1, 2);

    expected_steps = 5; % A complete block contains exactly 5 task triggers

    if length(block_events) < expected_steps
        valid_events(start_idx:end_idx, :) = [];
        disp('Deleted an incomplete/aborted trial block.');
    end
end

% [spm_opm_epoch_trigger] internally converted S.timewin to a trl matrix.
% We do the same here, but from our cleaned timeline instead of the raw onsets.
pre_trig_samp  = round((S.timewin(1) / 1000) * fs);
post_trig_samp = round((S.timewin(2) / 1000) * fs);

trl             = [];
conditionlabels = {};

for i = 1:size(valid_events, 1)
    onset   = valid_events(i, 1);
    cond_id = valid_events(i, 2);

    trl(end+1, :)          = [onset + pre_trig_samp, onset + post_trig_samp, pre_trig_samp];
    conditionlabels{end+1} = S.condLabels{cond_id};
end

% [spm_opm_epoch_trigger] called spm_eeg_epochs internally as its final step.
% We call it directly here with our custom trl matrix instead.
S.trl             = trl;
S.conditionlabels = conditionlabels;

epoch_bc_D = spm_eeg_epochs(S);


%% 3. Finish
disp('SUCCESS! Preprocessing complete.');
disp(['Final epoched and baseline-corrected file saved as: ', epoch_bc_D.fname]);
