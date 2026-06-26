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
S.condLabels      = {'CloseEyes', 'Stationary', 'PhysicallyWalk', 'EncodingRotate', 'ResponseRotate', 'ImagineWalk', 'OpenEyes', 'MasterSync'};
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
disp('Running trigger detection with fixed 3-second epochs...');
 
S                 = [];
S.D               = D1;
S.timewin         = [-200 3000];      % Cut from -200ms to +3000ms
S.bc              = 1;                % Apply baseline correction
% Only the 5 actual task conditions — skip T2 (CloseEyes), T8 (OpenEyes), T3 (Master Sync)
S.triggerChannels = {'T5', 'T8', 'T6', 'T9', 'T2', 'T10', 'T7'};
S.condLabels      = {'CloseEyes', 'Stationary', 'PhysicallyWalk', 'EncodingRotate', 'ResponseRotate', 'ImagineWalk', 'OpenEyes'};
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
% 3A. ALIGNMENT GUARD
% Drop any event that occurred before Motive started recording.
% -------------------------------------------------------------------------
pre_motive = all_events(:, 1) < t_zero;
if any(pre_motive)
    fprintf('Dropped %d event(s) that occurred before Motive started.\n', sum(pre_motive));
    all_events(pre_motive, :) = [];
end
 
 
% -------------------------------------------------------------------------
% 3B. NO CLEANUP NEEDED
%
% Since we're only detecting the 5 actual task condition triggers (T5, T6, T7, T9, T10),
% all detected events are valid epochs. No Close Eyes/Open Eyes validation required.
% -------------------------------------------------------------------------
valid_events = all_events;
 
 
% -------------------------------------------------------------------------
% 3C. BUILD trl MATRIX
%
% Standard 3-column trl matrix for SPM:
%   col 1: OPM epoch start sample
%   col 2: OPM epoch end sample
%   col 3: offset (where t=0 sits inside the epoch, relative to start)
% -------------------------------------------------------------------------
pre_trig_samp  = round((S.timewin(1) / 1000) * fs);
post_trig_samp = round((S.timewin(2) / 1000) * fs);
 
trl             = [];
conditionlabels = {};
 
for i = 1:size(valid_events, 1)
    onset   = valid_events(i, 1);
    cond_id = valid_events(i, 2);
 
    % Standard 3-column trl — SPM uses these to cut the .dat file
    trl(end+1, :)          = [onset + pre_trig_samp, ...
                               onset + post_trig_samp, ...
                               pre_trig_samp];
    conditionlabels{end+1} = S.condLabels{cond_id};
end
 
fprintf('Created %d total epochs.\n', size(trl, 1));
 
 
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
fprintf('\nMotive alignment calculation:\n');
fprintf('  t_zero (Motive start) = OPM sample %d\n', t_zero);
fprintf('  To convert trial onset to Motive time: (trial_onset_sample - %d) / %d\n', t_zero, fs);
 
 
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
