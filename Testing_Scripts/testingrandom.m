%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%   EPOCHING SCRIPT - RELATIVE TIME   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
 
 
%% HouseKeeping
clearvars
close all
pl=1;
 
% Change to your path format
addpath('C:/Users/ucjvmtu/Downloads/spm12') % MATLAB built-in function: Adds the specified folder to the search path.
spm('defaults','EEG') % External function (SPM12): Initializes SPM defaults specifically for M/EEG data.
 
cd('C:/Users/ucjvmtu/Downloads/spm12'); % MATLAB built-in function: Changes the current working directory.
 
%% 1. Import Raw Data
disp('Importing raw LVM file...');
 
S_create      = [];
S_create.data = 'imagination-run-004_array1.lvm';
D1            = spm_opm_create(S_create);
fs            = D1.fsample;
 
 
%% 2. Establish T=0 from All Triggers Sync Pulse
disp('Detecting all-triggers synchronization pulse (first occurrence = experiment start)...');
 
THRESH     = 0.05;
 
S.triggerChannels = {'T2', 'T5', 'T6', 'T7', 'T8', 'T9', 'T10', 'T3'};
S.condLabels      = {'CloseEyes', 'EncodingRotate', 'ResponseRotate', 'ImagineWalk', 'OpenEyes', 'Stationary', 'PhysicallyWalk', 'MasterSync'};
S.thresh          = THRESH;
 
chan_idx_all = D1.indchannel(S.triggerChannels);
trig_data_all = D1(chan_idx_all, :, 1);
 
t_zero = detectAllTriggersSync(trig_data_all, S.thresh, fs);
 
if isempty(t_zero)
    error('No all-triggers sync pulse detected. Motive was not recording.');
end
 
fprintf('Motive T=0 (mocap recording onset) at OPM sample %d (%.3f s into file).\n', t_zero, t_zero / fs);
 
 
%% 3. Trigger Detection with Onset/Offset Pairing
disp('Running trigger detection with onset/offset pairing...');
 
S                 = [];
S.D               = D1;
S.triggerChannels = {'T2', 'T5', 'T6', 'T7', 'T8', 'T9', 'T10'};
S.condLabels      = {'CloseEyes', 'EncodingRotate', 'ResponseRotate', 'ImagineWalk', 'OpenEyes', 'Stationary', 'PhysicallyWalk'};
S.thresh          = THRESH;
 
% Define onset → offset pairs
% CloseEyes (T2) → OpenEyes (T8)
% EncodingRotate (T5) → ResponseRotate (T6)
% ImagineWalk (T7) → Stationary (T9)
% PhysicallyWalk (T10) → OpenEyes (T8) OR back to idle?
S.onsetOffsetPairs = {
    1, 5;  % CloseEyes (T2) → OpenEyes (T8)
    2, 3;  % EncodingRotate (T5) → ResponseRotate (T6)
    4, 6;  % ImagineWalk (T7) → Stationary (T9)
    7, 5   % PhysicallyWalk (T10) → OpenEyes (T8)
};
 
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
% 3A. ALIGNMENT GUARD
% Drop any event that occurred before Motive started recording.
% -------------------------------------------------------------------------
pre_motive = all_events(:, 1) < t_zero;
if any(pre_motive)
    fprintf('Dropped %d event(s) that occurred before Motive started.\n', sum(pre_motive));
    all_events(pre_motive, :) = [];
end
 
 
% -------------------------------------------------------------------------
% 3B. CLEANUP — REDO TRIGGER DETECTION (with MARKING instead of deletion)
%
% Following SPM manual section 42.1-42.3: detect aborted trials and mark them
% as special events in the header, rather than deleting them
% -------------------------------------------------------------------------
valid_events = all_events;
rejected_trial_events = [];  % Store rejected trials as events [sample, trial_id]
 
% Re-load all 8 channels to detect redo triggers
chan_idx_all_8 = D1.indchannel({'T2', 'T5', 'T6', 'T7', 'T8', 'T9', 'T10', 'T3'});
trig_data_all_8 = D1(chan_idx_all_8, :, 1);
 
% Detect all redo triggers (all 8 channels HIGH simultaneously)
all_high = trig_data_all_8 > S.thresh;
all_channels_high = all(all_high, 1);
redo_triggers = find(diff(all_channels_high) == 1) + 1;
 
% Remove the first redo trigger (that's t_zero, not a redo)
if ~isempty(redo_triggers)
    redo_triggers(1) = [];
end
 
% Instead of deleting: MARK events that fall within aborted trial blocks
% These will be excluded later using 'Reject trials based on events' mode
for r = 1:length(redo_triggers)
    redo_sample = redo_triggers(r);
    % Find onset trigger after this redo
    next_onsets = find(valid_events(:, 1) > redo_sample);
    if ~isempty(next_onsets)
        % Mark all events from this redo block
        if r < length(redo_triggers)
            next_redo = redo_triggers(r+1);
            events_to_mark = find(valid_events(:, 1) > redo_sample & valid_events(:, 1) < next_redo);
        else
            % Last redo — mark until very end
            events_to_mark = find(valid_events(:, 1) > redo_sample);
        end
        
        for idx = events_to_mark'
            rejected_trial_events = [rejected_trial_events; valid_events(idx, 1), 1];
        end
    end
end
 
fprintf('Marked %d event(s) in aborted trial blocks (to be excluded later).\n', size(rejected_trial_events, 1));
 
 
% -------------------------------------------------------------------------
% 3C. BUILD TRIAL EPOCHS FROM ONSET/OFFSET PAIRS (with MARKED TRIALS)
%
% Following SPM manual section 12.8.1 and 42.1-42.3:
% trl includes ALL trials (valid + marked for rejection)
% Marked trials stored as events in header for later 'Reject trials based on events'
% -------------------------------------------------------------------------
 
trl             = [];
conditionlabels = {};
trial_status    = [];  % 1 = valid, 0 = marked as aborted
trial_info      = [];
 
for i = 1:size(valid_events, 1)
    onset_sample = valid_events(i, 1);
    onset_cond_id = valid_events(i, 2);
    
    % Find matching offset trigger for this onset
    offset_cond_id = [];
    
    for pair_idx = 1:size(S.onsetOffsetPairs, 1)
        if S.onsetOffsetPairs{pair_idx, 1} == onset_cond_id
            offset_cond_id = S.onsetOffsetPairs{pair_idx, 2};
            break
        end
    end
    
    if isempty(offset_cond_id)
        % This onset has no defined offset — skip it
        continue
    end
    
    % Look for the next occurrence of the offset trigger after this onset
    future_events = valid_events(i+1:end, :);
    matching_offsets = find(future_events(:, 2) == offset_cond_id, 1);
    
    if isempty(matching_offsets)
        % No matching offset found — mark as aborted
        fprintf('  Warning: No matching offset for %s at sample %d. Marking as aborted.\n', ...
            S.condLabels{onset_cond_id}, onset_sample);
        rejected_trial_events = [rejected_trial_events; onset_sample, 1];
        continue
    end
    
    offset_sample = future_events(matching_offsets, 1);
    
    % Check if this trial is marked as aborted
    is_aborted = any(rejected_trial_events(:, 1) == onset_sample);
    
    % Build the trl row
    trl(end+1, :)          = [onset_sample, offset_sample, 0];
    conditionlabels{end+1} = S.condLabels{onset_cond_id};
    trial_status(end+1)    = ~is_aborted;  % 1 = valid, 0 = aborted
    
    % Store trial metadata
    trial_duration = offset_sample - onset_sample;
    motive_elapsed = onset_sample - t_zero;
    
    trial_info(end+1, :) = [trial_duration, onset_cond_id, onset_sample, offset_sample, motive_elapsed, is_aborted];
end
 
fprintf('Created %d total trials (%d valid, %d marked as aborted).\n', ...
    size(trl, 1), sum(trial_status), size(trl, 1) - sum(trial_status));
 
 
% -------------------------------------------------------------------------
% 3D. EPOCH WITH SPM
% -------------------------------------------------------------------------
S.trl             = trl;
S.conditionlabels = conditionlabels;
epoch_D           = spm_eeg_epochs(S);
 
% -------------------------------------------------------------------------
% 3E. MARK ALL TRIALS AS EVENTS IN SPM HEADER (SPM Manual 42.1-42.3)
%
% Add trial status events to the epoched dataset header
% Each trial marked as either 'trial_accepted' or 'trial_aborted'
% -------------------------------------------------------------------------
disp('Adding trial status events to SPM header...');
 
% Add an event for each trial with its status
for i = 1:size(trl, 1)
    trial_onset = trl(i, 1);
    % Convert sample to time in seconds (relative to file start)
    event_time = trial_onset / fs;
    
    if trial_status(i) == 1
        % Valid/accepted trial
        trial_type = 'trial_accepted';
        trial_value = conditionlabels{i};
    else
        % Aborted/rejected trial
        trial_type = 'trial_aborted';
        trial_value = conditionlabels{i};
    end
    
    % Create event structure (following SPM format from section 42.1)
    event_struct.type = trial_type;
    event_struct.value = trial_value;
    event_struct.time = event_time;
    event_struct.duration = 0;
    
    epoch_D = epoch_D.addevent(event_struct);
end
 
% Save the updated dataset with trial status events
epoch_D = epoch_D.save;
 
% Save trial metadata
[fpath, fname_stem, ~] = fileparts(epoch_D.fname);
save(fullfile(fpath, [fname_stem '_trial_info.mat']), ...
     'trial_info', 't_zero', 'fs', 'conditionlabels', 'trial_status', 'S');
 
fprintf('Trial info and status saved to %s\n', fullfile(fpath, [fname_stem '_trial_info.mat']));
 
%% 4. Finish
disp('SUCCESS! Preprocessing complete.');
disp(['Final epoched file saved as: ', epoch_D.fname]);
disp('All trials marked in header as either trial_accepted or trial_aborted.');
fprintf('Event types: trial_accepted (valid), trial_aborted (rejected - no matching offset)\n');
fprintf('Use SPM "Detect artefacts" tool in "Reject" mode with "Reject trials based on events"\n');
fprintf('to filter to accepted trials only for downstream analysis.\n');
disp('Use trial_info.mat to normalize time within each trial (0-100% of trial duration).');
 
 
%% ========================================================================
%                      HELPER FUNCTION
%% ========================================================================
 
function t_zero = detectAllTriggersSync(trig_data_all, thresh, fs)
    % Detect the synchronization pulse where all 8 channels fire HIGH together.
    % Returns the sample index of the rising edge (experiment start).
    
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
