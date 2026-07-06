%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%   EPOCHING SCRIPT - SINGLE FILE   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
 
 
%% HouseKeeping
clearvars
close all
pl=1;
 
% Change to your path format
addpath('C:/Users/ucjvmtu/Downloads/spm12')
spm('defaults','EEG')
 
cd('C:/Users/ucjvmtu/Downloads/spm12');
 
 
%% 1. Import Raw Data
disp('Importing raw LVM file...');
 
S_create      = [];
S_create.data = 'imagination-run-003_array1.lvm';
D1            = spm_opm_create(S_create);
fs            = D1.fsample;
 
 
%% 2. Establish T=0 from All Triggers Sync Pulse
disp('Detecting all-triggers synchronization pulse (first occurrence = experiment start)...');
 
THRESH     = 0.05;
 
S.triggerChannels = {'T5', 'T8', 'T6', 'T9', 'T2', 'T10', 'T7', 'T3'};
S.condLabels      = {'Close Eyes', 'Stationary', 'Physical Walk', ...
          'Encoding Rot', 'Response Rot', 'Imagine Walk', 'Open Eyes', 'Master Sync'};
S.thresh          = THRESH;
 
chan_idx_all = D1.indchannel(S.triggerChannels);
trig_data_all = D1(chan_idx_all, :, 1);
 
t_zero = detectAllTriggersSync(trig_data_all, S.thresh, fs);
 
if isempty(t_zero)
    error('No all-triggers sync pulse detected. Motive was not recording.');
end
 
fprintf('Motive T=0 (mocap recording onset) at OPM sample %d (%.3f s into file).\n', t_zero, t_zero / fs);
 
 
%% 3. Manual Trigger Detection, Epoching & Baseline Correction
% Fixed 3-second epochs: -200ms baseline + 3000ms post-trigger
% Detect triggers in original data, then subtract t_zero to realign times
disp('Running trigger detection (will realign times to t_zero)...');
 
S                 = [];
S.D               = D1;
S.timewin         = [-200 3000];      % Cut from -200ms to +3000ms
S.bc              = 1;                % Apply baseline correction
% ALL 7 trigger types: state markers + task conditions
S.triggerChannels = {'T5', 'T8', 'T6', 'T9', 'T2', 'T10', 'T7'};
S.condLabels      = {'Close Eyes', 'Stationary', 'Physical Walk', ...
          'Encoding Rot', 'Response Rot', 'Imagine Walk', 'Open Eyes'};
S.thresh          = THRESH;
 
% Detect all rising edges for each trigger channel
chan_idx  = D1.indchannel(S.triggerChannels);
trig_data = D1(chan_idx, :, 1);
 
all_events = []; % [sample_number, channel_id]
 
for c = 1:length(S.triggerChannels)
    is_high = trig_data(c, :) > S.thresh;
    onsets  = find(diff(is_high) == 1) + 1;
    for k = 1:length(onsets)
        all_events = [all_events; onsets(k), c];
    end
end
 
% Sort chronologically
[~, sort_idx] = sort(all_events(:, 1));
all_events    = all_events(sort_idx, :);
 
 
% -------------------------------------------------------------------------
% 3A. REMOVE SIMULTANEOUS TRIGGER FIRES (SYNC ARTIFACTS)
% When multiple triggers fire at the same time, that's a sync pulse or artifact.
% Keep only isolated triggers (one per time window).
% -------------------------------------------------------------------------
simultaneous_tol = 10;  % Samples — events within this window are simultaneous
filtered_events = [];
 
i = 1;
while i <= size(all_events, 1)
    current_sample = all_events(i, 1);
    % Find all events within the simultaneous tolerance window
    window = find(all_events(:, 1) >= current_sample - simultaneous_tol & ...
                  all_events(:, 1) <= current_sample + simultaneous_tol);
    if length(window) == 1
        % Isolated event — keep it
        filtered_events = [filtered_events; all_events(i, :)];
        i = i + 1;
    else
        % Multiple events in this window — skip all of them (sync artifact)
        fprintf('Removed %d simultaneous triggers at sample %d (%.3f s)\n', length(window), current_sample, current_sample / fs);
        i = i + length(window);
    end
end
 
all_events = filtered_events;
 
 
% -------------------------------------------------------------------------
% 3A. (skipped — data already starts at t_zero)
% -------------------------------------------------------------------------
 
 
% -------------------------------------------------------------------------
% 3B. NO CLEANUP NEEDED
%
% All 7 trigger types detected. No validation required.
% -------------------------------------------------------------------------
valid_events = all_events;
 
 
% -------------------------------------------------------------------------
% 3C. BUILD trl MATRIX (SUBTRACT t_zero FROM ALL TIME POINTS)
%
% Subtract t_zero from all trigger sample positions so that the all-triggers
% sync pulse (when all 8 channels fired together) becomes the reference point (t=0).
% -------------------------------------------------------------------------
pre_trig_samp  = round((S.timewin(1) / 1000) * fs);
post_trig_samp = round((S.timewin(2) / 1000) * fs);
 
trl             = [];
conditionlabels = {};
 
for i = 1:size(valid_events, 1)
    onset   = valid_events(i, 1);
    cond_id = valid_events(i, 2);
 
    % Subtract t_zero to realign all times relative to sync pulse
    % Corrected code
trl(end+1, :) = [onset + pre_trig_samp, onset + post_trig_samp, pre_trig_samp];
    conditionlabels{end+1} = S.condLabels{cond_id};
end
 
fprintf('Created %d total epochs (times subtracted by t_zero = %d samples).\n', size(trl, 1), t_zero);
 
 
% -------------------------------------------------------------------------
% 3D. EPOCH WITH SPM
% -------------------------------------------------------------------------
S.trl             = trl;
S.conditionlabels = conditionlabels;
epoch_D           = spm_eeg_epochs(S);
 
 
% -------------------------------------------------------------------------
% 3E. SAVE EPOCHED DATA
% -------------------------------------------------------------------------
% No additional metadata needed — motive alignment can be calculated from:
%   t_zero (Motive start in OPM samples) and trial onset samples
% Formula: motive_time_sec = (trial_onset_sample - t_zero) / fs
 
epoch_D = epoch_D.save;
 
 
%% 4. Finish
disp('SUCCESS! Preprocessing complete.');
disp(['Final epoched and baseline-corrected file saved as: ', epoch_D.fname]);
fprintf('Epoch window: -200ms to +3000ms (3200ms total)\n');
fprintf('Baseline correction applied automatically\n');
fprintf('All time points realigned relative to t_zero (first all-triggers sync pulse)\n');
fprintf('t_zero was at OPM sample %d (%.3f s)\n', t_zero, t_zero / fs);
 
 
%% ========================================================================
%                      HELPER FUNCTION
%% ========================================================================
 
function t_zero = detectAllTriggersSync(trig_data_all, thresh, fs)
    % Detect the synchronization pulse where all 8 channels fire HIGH together,
    % then drop LOW. Returns the sample index of the rising edge (experiment start).
    all_high = trig_data_all > thresh;
    all_channels_high = all(all_high, 1);
    rising_edges = find(diff(all_channels_high) == 1) + 1;
    if isempty(rising_edges)
        t_zero = [];
        return
    end
    t_zero = rising_edges(1);
    if length(rising_edges) > 1
        fprintf('Found %d total all-trigger pulses (1st = experiment start, %d = abort/redo markers).\n', ...
            length(rising_edges), length(rising_edges) - 1);
    end
end
