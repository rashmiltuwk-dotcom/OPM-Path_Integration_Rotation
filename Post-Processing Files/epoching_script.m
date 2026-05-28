
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%   DISCUSSION FOR EPOCHING SCRIPT   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% The SPM documentation states "if your conditions are defined in a more complicated way than just based on a single
% trigger you should write your own code that will output a file with trl and conditionlabels variables and that file
% can then be used as input to epoching." So we would have to make our manual trl matrix rather than utilising the
% spm_opm_epoch_trigger function. https://www.fil.ion.ucl.ac.uk/spm/docs/manual/meeg/eeg_preprocessing/


% Custom trial function logic is also supported by FieldTrip (toolbox embedded in SPM12), with the function 
% ft_definetrial(). https://www.fieldtriptoolbox.org/example/preproc/trialfun/

% We need to make sure that the structuring of the trial complies with the FieldTrip format.
% Which is: one row per trial and three columns representing the sample numbers from the start of the continuous
% recording for onset, offset, and pre-stimulus baseline period.

% The T8 logic complies with alignmnent logic of kinematic and OPM data; where the formula is 
% motive_onset = onset - t_zero
% This allows data to be accurately aligned with OptiTrack data in later analysis steps.
% t_zero is taken from the trigger's first onset value (shown : t_zero = t_zero(1); % Take the first rising edge only)
% ^ same logic applied to other trigger-based events
% onsets  = find(diff(is_high) == 1) + 1;
% for k = 1:length(onsets)
%     all_events = [all_events; onsets(k), c];


% the fourth, fifth and sixth columns give the motive onset, motive epoch start and motive epoch end respectively

% For ensuring the data collected isn't that of the trial that was redone, we apply the following logic:
% If a participant aborted early (e.g. started Open Eyes (First Trigger (T2)) and didn't complete task
% steps enough to get to Close Eyes (First Trigger (T2))), the required channels won't be found between the
% bookends. Hence, the entire trial is deleted.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%% HouseKeeping
clearvars
close all
pl=1;

addpath('/Users/rashmil/Documents/MATLAB')
spm('defaults','EEG')
cd('/Users/rashmil/Documents/MATLAB');


%% 1. Import Raw Data
disp('Importing raw LVM file...');

S_create      = [];
S_create.data = 'log-run-003_array1.lvm';
D1            = spm_opm_create(S_create);
fs            = D1.fsample;


%% 2. Establish T=0 from Motive Span (T8)
% T8 goes HIGH the moment Motive starts recording. Its rising edge is the
% single shared event between the two hardware clocks — it is the only
% sample number that means the same thing in both the OPM file and the
% Motive .csv file (row 1 of Motive = t_zero in OPM samples).
disp('Detecting Motive span onset (T8)...');

THRESH     = 0.05;
trig8_data = D1(D1.indchannel('T8'), :, 1);
t_zero     = find(diff(trig8_data > THRESH) == 1) + 1;

if isempty(t_zero)
    error('No T8 rising edge detected. Motive was not recording.');
end

t_zero = t_zero(1);
fprintf('Motive T=0 at OPM sample %d (%.3f s into file).\n', t_zero, t_zero / fs);


%% 3. Epoch & Baseline Step
disp('Running manual trigger detection, epoching, and baseline correction...');

S                 = [];
S.D               = D1;
S.timewin         = [-200 3000];
S.bc              = 1;
% T8  excluded — handled above as the Motive anchor, not a stimulus.
% T9  excluded — backup master sync only.
% T10 excluded — backup master sync only.
% T2  = Close Eyes / Open Eyes bookend channel.
% T3, T4, T5, T6, T7 = task stimulus channels fired during each trial.
S.triggerChannels = {'T2', 'T3', 'T4', 'T5', 'T6', 'T7'};
S.condLabels      = {'EyesInstruction', 'Stationary', 'PhysicallyWalk', 'EncodingRotate', 'ResponseRotate', 'ImagineWalk'};
S.thresh          = THRESH;

% [spm_opm_epoch_trigger] resolved channel names to row indices internally
chan_idx  = D1.indchannel(S.triggerChannels);
trig_data = D1(chan_idx, :, 1);

% [spm_opm_epoch_trigger] detected rising edges internally
% We replicate this here so we can intercept the timeline
all_events = []; % [sample_number, channel_id]

for c = 1:length(S.triggerChannels)
    is_high = trig_data(c, :) > S.thresh;
    onsets  = find(diff(is_high) == 1) + 1;
    for k = 1:length(onsets)
        all_events = [all_events; onsets(k), c];
    end
end

[~, sort_idx] = sort(all_events(:, 1));
all_events    = all_events(sort_idx, :);


% -------------------------------------------------------------------------
% 3A. ALIGNMENT GUARD
% Drop any event that occurred before Motive started recording.
% These have no corresponding motion frame — keeping them would produce
% epochs with a valid brain signal but no alignable kinematics data.
% -------------------------------------------------------------------------
pre_motive = all_events(:, 1) < t_zero;
if any(pre_motive)
    fprintf('Dropped %d event(s) that occurred before Motive started.\n', sum(pre_motive));
    all_events(pre_motive, :) = [];
end


% -------------------------------------------------------------------------
% 3B. CLEANUP — T2 BOOKEND METHOD
%
% T2 (channel ID 1) is pressed TWICE per trial:
%   First press  = Close Eyes = block START
%   Second press = Open Eyes  = block END
%
% Between those two T2 presses, every task channel must have fired
% at least once for the trial to be considered complete:
%   T3 (ID 2), T4 (ID 3), T5 (ID 4), T6 (ID 5), T7 (ID 6)
%
% required_channels is stated explicitly here rather than inferred from
% valid_events — T8, T9, T10 were never scanned so they do not appear
% in valid_events and cannot be used to derive the required set.
%
% If a participant aborted early (pressed Open Eyes before completing all
% task steps), one or more required channels will be absent between the
% bookends. The entire block is deleted in that case.
% -------------------------------------------------------------------------
valid_events = all_events;
ch1_id            = 1;              % T2 = bookend channel (ID 1 in triggerChannels)
required_channels = [2, 3, 4, 5, 6, 7]; % T3, T4, T5, T6, T7 must all fire inside a block

% Find every row in the timeline where T2 was pressed
ch1_indices = find(valid_events(:, 2) == ch1_id);

% Guard: if T2 was pressed an odd number of times the final block was
% never closed (recording ended before Open Eyes). Drop it entirely.
if mod(length(ch1_indices), 2) ~= 0
    valid_events(ch1_indices(end):end, :) = [];
    disp('WARNING: Dropped incomplete final block (odd number of T2 presses).');
end

% Recompute after the guard so indices reflect the trimmed valid_events
ch1_indices = find(valid_events(:, 2) == ch1_id);

% Loop backwards through T2 pairs so that deleting a block does not
% corrupt the row indices of pairs we have not yet visited
for i = length(ch1_indices)-1 : -2 : 1

    start_idx = ch1_indices(i);    % row of Close Eyes (first T2)
    end_idx   = ch1_indices(i+1); % row of Open Eyes  (second T2)

    % Pull out only the channel IDs that fired BETWEEN the two bookends
    % (start_idx+1 and end_idx-1 exclude the bookends themselves)
    block_events = valid_events(start_idx+1 : end_idx-1, 2);

    % Check whether every required channel appears at least once.
    % ismember returns true for each required channel found in block_events.
    % If any required channel is missing, all() returns false.
    if ~all(ismember(required_channels, block_events))
        % At least one task channel did not fire — trial was aborted.
        % Delete everything from Close Eyes to Open Eyes inclusive.
        valid_events(start_idx:end_idx, :) = [];
        disp('Deleted an incomplete/aborted trial block.');
    end
end


% -------------------------------------------------------------------------
% 3C. BUILD trl MATRIX AND MOTIVE ALIGNMENT
%
% trl is kept as a standard 3-column matrix as SPM requires:
%   col 1: OPM epoch start sample
%   col 2: OPM epoch end sample
%   col 3: offset (where t=0 sits inside the epoch)
%
% Motive alignment is stored separately in motive_info (N x 3):
%   col 1: elapsed OPM samples from Motive start to stimulus onset
%   col 2: elapsed OPM samples from Motive start to epoch start (-200ms)
%   col 3: elapsed OPM samples from Motive start to epoch end (+3000ms)
%
% motive_info row N corresponds exactly to trl row N.
% To convert any motive_info value to seconds:       value / fs
% To convert to Motive frames downstream:            round((value / fs) * fs_motive)
% -------------------------------------------------------------------------
pre_trig_samp  = round((S.timewin(1) / 1000) * fs);
post_trig_samp = round((S.timewin(2) / 1000) * fs);

trl             = [];
conditionlabels = {};
motive_info     = [];

for i = 1:size(valid_events, 1)
    onset   = valid_events(i, 1);
    cond_id = valid_events(i, 2);

    % Standard 3-column trl — SPM uses these to cut the .dat file
    trl(end+1, :)          = [onset + pre_trig_samp, ...
                               onset + post_trig_samp, ...
                               pre_trig_samp];
    conditionlabels{end+1} = S.condLabels{cond_id};

    % Motive alignment — parallel matrix, same row order as trl
    % pre_trig_samp is negative so motive_epoch_start steps back correctly
    motive_onset       = onset - t_zero;
    motive_epoch_start = motive_onset + pre_trig_samp;
    motive_epoch_end   = motive_onset + post_trig_samp;

    motive_info(end+1, :) = [motive_onset, motive_epoch_start, motive_epoch_end];
end

% Save Motive alignment to a separate file.
% motive_info row N maps directly to trl row N.
save('motive_alignment.mat', 'motive_info', 't_zero', 'conditionlabels');

% [spm_opm_epoch_trigger] called spm_eeg_epochs internally.
% We call it directly with our standard 3-column trl matrix.
S.trl             = trl;
S.conditionlabels = conditionlabels;
epoch_bc_D        = spm_eeg_epochs(S);


%% 4. Finish
disp('SUCCESS! Preprocessing complete.');
disp(['Final epoched and baseline-corrected file saved as: ', epoch_bc_D.fname]);
fprintf('Motive alignment saved to motive_alignment.mat for %d trials.\n', size(trl, 1));
