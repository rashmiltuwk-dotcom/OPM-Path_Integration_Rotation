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

% The motive span onset logic complies with alignment logic of kinematic and OPM data; where the formula is
% motive_onset = onset - t_zero
% This allows data to be accurately aligned with OptiTrack data in later analysis steps.
% t_zero is taken from the trigger's first onset value (shown : t_zero = t_zero(1); % Take the first rising edge only)
% ^ same logic applied to other trigger-based events
% onsets  = find(diff(is_high) == 1) + 1;
% for k = 1:length(onsets)
%     all_events = [all_events; onsets(k), c];

% The fourth, fifth and sixth columns of motive_info give the motive onset, motive epoch start and
% motive epoch end respectively. motive_info is saved separately to preserve the standard 3-column
% trl matrix required by SPM/FieldTrip. motive_info row N corresponds exactly to trl row N.
% The alignment file is named after the epoched file it belongs to so the two are unambiguously linked.

% For ensuring the data collected isn't that of the trial that was redone, we apply the following logic:
% If a participant aborted early (e.g. pressed Close Eyes (T2) before completing all task steps and getting to Open Eyes (T8)),
% the required channels won't all be found between the bookends.
% Hence, the entire trial block is deleted.

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


%% 2. Establish T=0 from Motive Span (A1)
% A1 goes HIGH the moment Motive starts recording. Its rising edge is the
% single shared event between the two hardware clocks — it is the only
% sample number that means the same thing in both the OPM file and the
% Motive .csv file (row 1 of Motive = t_zero in OPM samples).
disp('Detecting Motive span onset (CHECK VIEW SCRIPT TO IDENTIFY CORRECT CHANNEL)...');

THRESH     = 0.05;
trigMotive_data = D1(D1.indchannel('A1'), :, 1);
t_zero     = find(diff(trigMotive_data > THRESH) == 1) + 1;

if isempty(t_zero)
    error('No Motive rising edge detected. Motive was not recording.');
end

t_zero = t_zero(1);
fprintf('Motive T=0 (mocap recording onset) at OPM sample %d (%.3f s into file).\n', t_zero, t_zero / fs);


%% 2. Manual Trigger Detection, Epoching & Baseline Correction
% This section replicates and extends what spm_opm_epoch_trigger does
% internally, exposing the timeline so aborted trials can be removed
% before SPM cuts the data.
disp('Running manual trigger detection, epoching, and baseline correction...');

S                 = [];
S.D               = D1;
S.timewin         = [-200 3000];      % Cut from -200ms to +3000ms
S.bc              = 1;                % 1 = Yes, apply baseline correction automatically
% T2  = Close Eyes (bookend START, ID 1)
% T3  = Stationary (ID 2)
% T4  = PhysicallyWalk (ID 3)
% T5  = EncodingRotate (ID 4)
% T6  = ResponseRotate (ID 5)
% T7  = ImagineWalk (ID 6)
% T8  = Open Eyes (bookend END, ID 7)
S.triggerChannels = {'T2',              'T3',          'T4',            'T5',              'T6',             'T7',          'T8'};
S.condLabels      = {'CloseEyes', 'Stationary',  'PhysicallyWalk','EncodingRotate',  'ResponseRotate', 'ImagineWalk', 'OpenEyes'};
S.thresh          = THRESH;

% [spm_opm_epoch_trigger] resolved channel names to row indices internally
chan_idx  = D1.indchannel(S.triggerChannels);
trig_data = D1(chan_idx, :, 1);

% [spm_opm_epoch_trigger] detected rising edges internally
% We replicate this here so we can intercept the timeline
all_events = []; % [sample_number, channel_id]

for c = 1:length(S.triggerChannels)
    is_high = trig_data(c, :) > S.thresh;          % [spm_opm_epoch_trigger] threshold crossing
    onsets  = find(diff(is_high) == 1) + 1;         % [spm_opm_epoch_trigger] rising edge detection
    for k = 1:length(onsets)
        all_events = [all_events; onsets(k), c];
    end
end

% Sort all events into a true chronological timeline
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
% 3B. CLEANUP — CLOSE EYES / OPEN EYES BOOKEND METHOD
%
% T2 (channel ID 1) = Close Eyes = block START
% T8 (channel ID 7) = Open Eyes  = block END
%
% A complete trial requires: Close Eyes → [task events] → Open Eyes
% Any incomplete block (Close Eyes without matching Open Eyes) is deleted entirely.
% -------------------------------------------------------------------------
valid_events = all_events;
closeEyes_id = 1;  % T2
openEyes_id  = 7;  % T8

% Find all Close Eyes
closeEyes_indices = find(valid_events(:, 2) == closeEyes_id);

% Loop backwards to avoid index corruption when deleting rows
for i = length(closeEyes_indices) : -1 : 1
    close_eyes_idx = closeEyes_indices(i);
    
    % Find the next Open Eyes after this Close Eyes
    open_eyes_after = find(valid_events(close_eyes_idx+1:end, 2) == openEyes_id, 1);
    
    if isempty(open_eyes_after)
        % No matching Open Eyes — delete the entire block
        % Block ends at: next Close Eyes (if exists) or end of valid_events
        next_close_eyes = find(valid_events(close_eyes_idx+1:end, 2) == closeEyes_id, 1);
        
        if isempty(next_close_eyes)
            % No next Close Eyes — delete from here to end
            delete_end_idx = size(valid_events, 1);
        else
            % Delete up to (but not including) the next Close Eyes
            delete_end_idx = close_eyes_idx + next_close_eyes - 1;
        end
        
        valid_events(close_eyes_idx:delete_end_idx, :) = [];
        disp('Deleted incomplete trial block (Close Eyes without matching Open Eyes).');
    end
end


% -------------------------------------------------------------------------
% 3C. BUILD trl MATRIX AND MOTIVE ALIGNMENT
%
% trl is kept as a standard 3-column matrix as SPM/FieldTrip requires:
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

% [spm_opm_epoch_trigger] called spm_eeg_epochs internally.
% We call it directly with our standard 3-column trl matrix.
S.trl             = trl;
S.conditionlabels = conditionlabels;
epoch_bc_D        = spm_eeg_epochs(S);

% Save Motive alignment named after the epoched file so the two are
% unambiguously linked on disk. motive_info row N maps to trl row N.
[fpath, fname_stem, ~] = fileparts(epoch_bc_D.fname);
save(fullfile(fpath, [fname_stem '_motive_alignment.mat']), ...
     'motive_info', 't_zero', 'conditionlabels');


%% 3. Finish
disp('SUCCESS! Preprocessing complete.');
disp(['Final epoched and baseline-corrected file saved as: ', epoch_bc_D.fname]);
fprintf('Motive alignment saved to %s\n', fullfile(fpath, [fname_stem '_motive_alignment.mat']));
