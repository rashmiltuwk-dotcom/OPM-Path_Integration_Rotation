%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%   EPOCHING SCRIPT - SINGLE FILE
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%% HouseKeeping
clearvars
close all
pl=1;

addpath('C:/Users/spaceandmem/rashmil_opm/spm/')
addpath('C:/Users/spaceandmem/rashmil_opm/data_dump/')
spm('defaults','EEG')

cd('C:/Users/spaceandmem/rashmil_opm/data_dump/');


%% 1. Import Raw Data
disp('Importing raw LVM file...');

lvmFile       = 'imagination-run-003_001.lvm';
S_create      = [];
S_create.data = lvmFile;
D1            = spm_opm_create(S_create);
fs            = D1.fsample;


%% 1A. Determine Block Number from LVM Filename
[~, lvmName, ~] = fileparts(lvmFile);
lvmParts        = strsplit(lvmName, '_');
blockNum        = str2double(lvmParts{end});

if isnan(blockNum)
    error('Could not parse block number from LVM filename ''%s''.', lvmFile);
end

fprintf('LVM file indicates block %d.\n', blockNum);


%% 1B. Load Behavioral Master Data — matched by block number
disp('Locating MasterData file for this block...');

masterDataFiles = dir('*_MasterData.mat');
matchIdx        = [];

for f = 1:length(masterDataFiles)
    parts = strsplit(masterDataFiles(f).name, '_');
    if numel(parts) >= 2 && str2double(parts{2}) == blockNum
        matchIdx(end+1) = f; %#ok<AGROW>
    end
end

if isempty(matchIdx)
    error('No MasterData file found for block %d.', blockNum);
elseif numel(matchIdx) > 1
    error('Multiple MasterData files found for block %d: %s', ...
        blockNum, strjoin({masterDataFiles(matchIdx).name}, ', '));
end

masterDataFile = masterDataFiles(matchIdx).name;
fprintf('Using MasterData file: %s\n', masterDataFile);

loaded         = load(masterDataFile);
MasterData     = loaded.MasterData;
n_trials_meta  = numel(MasterData);


%% 2. Establish T=0 and genuine abort/redo markers (all 8 channels together)
disp('Detecting all-triggers synchronization pulse...');

THRESH           = 0.05;
simultaneous_tol = 10;

S.triggerChannels = {'T5', 'T8', 'T6', 'T9', 'T2', 'T10', 'T7', 'T3'};
S.condLabels      = {'Close Eyes', 'Stationary', 'Physical Walk', ...
          'Encoding Rot', 'Response Rot', 'Imagine Walk', 'Open Eyes', 'Master Sync'};
S.thresh          = THRESH;

chan_idx_all  = D1.indchannel(S.triggerChannels);
trig_data_all = D1(chan_idx_all, :, 1);

[t_zero, real_abort_markers] = detectAllTriggersSync(trig_data_all, S.thresh, simultaneous_tol);

if isempty(t_zero)
    error('No all-triggers sync pulse detected. Motive was not recording.');
end

fprintf('Motive T=0 (mocap recording onset) at OPM sample %d (%.3f s into file).\n', t_zero, t_zero / fs);
fprintf('Genuine abort/redo markers (all 8 channels within %d samples of each other): %d found.\n', ...
    simultaneous_tol, numel(real_abort_markers));


%% 3. Manual Trigger Detection, Epoching & Baseline Correction
disp('Running trigger detection (will realign times to t_zero)...');

S                 = [];
S.D               = D1;
S.timewin         = [-200 3000];
S.bc              = 1;
S.triggerChannels = {'T5', 'T8', 'T6', 'T9', 'T2', 'T10', 'T7'};
S.condLabels      = {'Close Eyes', 'Stationary', 'Physical Walk', ...
          'Encoding Rot', 'Response Rot', 'Imagine Walk', 'Open Eyes'};
S.thresh          = THRESH;

CLOSE_EYES_ID = find(strcmp(S.condLabels, 'Close Eyes'));
OPEN_EYES_ID  = find(strcmp(S.condLabels, 'Open Eyes'));

chan_idx  = D1.indchannel(S.triggerChannels);
trig_data = D1(chan_idx, :, 1);

all_events = [];

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
% 3A. REMOVE ARTIFACT DUPLICATES CAUSED BY GENUINE ABORT/REDO PULSES
% -------------------------------------------------------------------------
filtered_events  = [];

for i = 1:size(all_events, 1)
    sample = all_events(i, 1);
    is_artifact_of_real_abort = any(abs(real_abort_markers - sample) <= simultaneous_tol);
    if ~is_artifact_of_real_abort
        filtered_events = [filtered_events; all_events(i, :)]; %#ok<AGROW>
    else
        fprintf('Removed event at sample %d (%.3f s) — coincides with genuine abort/redo marker.\n', ...
            sample, sample / fs);
    end
end

all_events   = filtered_events;
valid_events = all_events;
abort_markers = real_abort_markers;


% -------------------------------------------------------------------------
% 3B-i. FIND CLOSE/OPEN EYES COINCIDENCES (simultaneous firing)
% -------------------------------------------------------------------------
close_idx = find(valid_events(:, 2) == CLOSE_EYES_ID);
open_idx  = find(valid_events(:, 2) == OPEN_EYES_ID);

if length(close_idx) ~= length(open_idx)
    error('Found %d Close Eyes triggers but %d Open Eyes triggers — cannot pair trials.', ...
        length(close_idx), length(open_idx));
end

close_onsets = valid_events(close_idx, 1);
open_onsets  = valid_events(open_idx, 1);
n_pairs = length(close_onsets);

close_consumed = false(n_pairs, 1);
open_consumed  = false(n_pairs, 1);

trial_status = cell(size(valid_events, 1), 1);
trial_meta   = repmat(struct('TrialNum',[],'TaskType','','Direction','','Quadrant','','Distance',[]), ...
                       size(valid_events, 1), 1);

remove_rows = [];
n_pause   = 0;
n_realign_dropped = 0;

for ci = 1:n_pairs
    if close_consumed(ci), continue; end
    match = find(~open_consumed & abs(open_onsets - close_onsets(ci)) <= simultaneous_tol, 1);
    if ~isempty(match)
        close_consumed(ci)   = true;
        open_consumed(match) = true;

        coincidence_sample = round((close_onsets(ci) + open_onsets(match)) / 2);
        span_lo = min(close_onsets(ci), open_onsets(match));
        span_hi = max(close_onsets(ci), open_onsets(match));
        in_span = find(valid_events(:,1) >= span_lo & valid_events(:,1) <= span_hi);

        if abs(coincidence_sample - t_zero) <= simultaneous_tol
            remove_rows = [remove_rows; in_span]; %#ok<AGROW>
            n_realign_dropped = n_realign_dropped + numel(in_span);
            fprintf('Close/Open coincidence at sample %d matches t_zero — DROPPED (realign artifact, not epoched).\n', ...
                coincidence_sample);
        else
            n_pause = n_pause + 1;
            meta = struct('TrialNum', NaN, 'TaskType', 'PAUSED', 'Direction', '', 'Quadrant', '', 'Distance', NaN);
            [trial_status{in_span}] = deal('PAUSED');
            [trial_meta(in_span)]   = deal(meta);
            fprintf('Close/Open coincidence at sample %d — labeled PAUSED.\n', coincidence_sample);
        end
    end
end

real_close_pos = find(~close_consumed);
real_open_pos  = find(~open_consumed);

if length(real_close_pos) ~= length(real_open_pos)
    error('After removing %d pause/realign coincidences, found %d remaining Close Eyes but %d remaining Open Eyes — cannot pair real trials.', ...
        n_pause + 1, length(real_close_pos), length(real_open_pos));
end

n_real_spans = length(real_close_pos);
fprintf('Found %d total Close/Open Eyes onsets: %d real trial spans, %d pause, %d realign events dropped.\n', ...
    n_pairs, n_real_spans, n_pause, n_realign_dropped);

if n_real_spans ~= n_trials_meta
    error('Found %d REAL trial spans (excluding %d pause coincidences and %d dropped realign events) in the trigger data but MasterData has %d trials — behavioral log and trigger record are out of sync.', ...
        n_real_spans, n_pause, n_realign_dropped, n_trials_meta);
end


% -------------------------------------------------------------------------
% 3B-ii. LABEL REAL TRIALS (ACCEPTED / REJECTED) — only touch unlabeled events
% -------------------------------------------------------------------------
masterDataIdx = 0;

for k = 1:n_real_spans
    ci = real_close_pos(k);
    oi = real_open_pos(k);
    trial_start_samp = close_onsets(ci);
    trial_end_samp   = open_onsets(oi);

    if trial_end_samp <= trial_start_samp
        error('Real trial span has Open Eyes at sample %d before Close Eyes at sample %d.', ...
            trial_end_samp, trial_start_samp);
    end

    in_trial = find(valid_events(:, 1) >= trial_start_samp & valid_events(:, 1) <= trial_end_samp);

    already_labeled = ~cellfun(@isempty, trial_status(in_trial));
    in_trial_unlabeled = in_trial(~already_labeled);

    masterDataIdx = masterDataIdx + 1;
    was_aborted = any(abort_markers > trial_start_samp & abort_markers < trial_end_samp);
    if was_aborted
        status_label = 'REJECTED';
    else
        status_label = 'ACCEPTED';
    end
    meta = buildTrialMeta(MasterData, masterDataIdx);

    [trial_status{in_trial_unlabeled}] = deal(status_label);
    [trial_meta(in_trial_unlabeled)]   = deal(meta);
end


% -------------------------------------------------------------------------
% 3B-iii. DROP REALIGN ROWS FROM EVERYTHING before epoching
% -------------------------------------------------------------------------
if ~isempty(remove_rows)
    remove_rows = unique(remove_rows);
    valid_events(remove_rows, :) = [];
    trial_status(remove_rows)    = [];
    trial_meta(remove_rows)      = [];
end

if any(cellfun(@isempty, trial_status))
    n_orphan = sum(cellfun(@isempty, trial_status));
    error('%d trigger event(s) got no status assigned — check trigger integrity.', n_orphan);
end

n_accepted = sum(strcmp(trial_status, 'ACCEPTED'));
n_rejected = sum(strcmp(trial_status, 'REJECTED'));
n_paused   = sum(strcmp(trial_status, 'PAUSED'));
fprintf('Trial status (all events): %d ACCEPTED, %d REJECTED, %d PAUSED.\n', ...
    n_accepted, n_rejected, n_paused);


% -------------------------------------------------------------------------
% 3B-iv. t_zero SUBTRACTION — the ONE computed value, reused everywhere
% -------------------------------------------------------------------------
timeRelSec = (valid_events(:,1) - t_zero) / fs;


% -------------------------------------------------------------------------
% 3C. BUILD trl MATRIX (trl stays ABSOLUTE — required by spm_eeg_epochs)
% -------------------------------------------------------------------------
pre_trig_samp  = round((S.timewin(1) / 1000) * fs);
post_trig_samp = round((S.timewin(2) / 1000) * fs);

trl             = [];
conditionlabels = {};

for i = 1:size(valid_events, 1)
    onset   = valid_events(i, 1);
    cond_id = valid_events(i, 2);

    trl(end+1, :) = [onset + pre_trig_samp, onset + post_trig_samp, pre_trig_samp]; %#ok<AGROW>

    if strcmp(trial_status{i}, 'PAUSED')
        conditionlabels{end+1} = 'PAUSED'; %#ok<AGROW>
    else
        conditionlabels{end+1} = S.condLabels{cond_id}; %#ok<AGROW>
    end
end

fprintf('Created %d total epochs (realign events excluded entirely).\n', size(trl, 1));


% -------------------------------------------------------------------------
% 3D. EPOCH WITH SPM
% -------------------------------------------------------------------------
S.trl             = trl;
S.conditionlabels = conditionlabels;
epoch_D           = spm_eeg_epochs(S);


% -------------------------------------------------------------------------
% 3D-i. ATTACH STATUS + METADATA AS EVENTS — .time = t_zero-relative seconds
%
% CHANGED: PAUSED is a LABEL only (already correctly set as the
% conditionlabel in 3C) — it is NOT a status event. Only ACCEPTED/
% REJECTED trials get a status event attached here now.
% -------------------------------------------------------------------------
disp('Attaching status and MasterData fields as events per trial (time = t_zero-relative seconds)...');

metaFields = {'TrialNum','TaskType','Direction','Quadrant','Distance'};

for t = 1:size(trl, 1)
    ev = struct('type', {}, 'value', {}, 'time', {}, 'duration', {});
    thisTime = timeRelSec(t);

    % Only ACCEPTED/REJECTED get a status event — PAUSED is a label
    % (conditionlabel), never a status.
    if ~strcmp(trial_status{t}, 'PAUSED')
        statusEv.type     = trial_status{t};
        statusEv.value    = 1;
        statusEv.time     = thisTime;
        statusEv.duration = 0;
        ev(end+1) = statusEv; %#ok<AGROW>
    end

    for f = 1:numel(metaFields)
        fieldEv.type     = metaFields{f};
        fieldEv.value    = trial_meta(t).(metaFields{f});
        fieldEv.time     = thisTime;
        fieldEv.duration = 0;
        ev(end+1) = fieldEv; %#ok<AGROW>
    end

    epoch_D = events(epoch_D, t, ev);
end


% -------------------------------------------------------------------------
% 3D-ii. SET trialonset TO t_zero-RELATIVE TIME
% -------------------------------------------------------------------------
disp('Setting trialonset to t_zero-relative time for every epoch...');

for t = 1:size(trl, 1)
    epoch_D = trialonset(epoch_D, t, timeRelSec(t));
end


% -------------------------------------------------------------------------
% 3E. SAVE EPOCHED DATA
% -------------------------------------------------------------------------
epoch_D = epoch_D.save();


%% 4. Finish
disp('SUCCESS! Preprocessing complete.');
disp(['Final epoched and baseline-corrected file saved as: ', epoch_D.fname]);
fprintf('Each trial: ONE event, type=status (ACCEPTED/REJECTED/PAUSED), value={TrialNum,TaskType,Direction,Quadrant,Distance}.\n');


%% ========================================================================
%                      HELPER FUNCTIONS
%% ========================================================================

function [t_zero, abort_markers] = detectAllTriggersSync(trig_data_all, thresh, tol)
    nChan = size(trig_data_all, 1);

    all_edges = [];
    for c = 1:nChan
        is_high = trig_data_all(c, :) > thresh;
        onsets  = find(diff(is_high) == 1) + 1;
        all_edges = [all_edges; onsets(:), repmat(c, numel(onsets), 1)]; %#ok<AGROW>
    end

    if isempty(all_edges)
        t_zero = [];
        abort_markers = [];
        return
    end

    all_edges = sortrows(all_edges, 1);

    rising_edges = [];
    i = 1;
    while i <= size(all_edges, 1)
        j = i;
        chans_seen = all_edges(i, 2);
        while j + 1 <= size(all_edges, 1) && (all_edges(j+1, 1) - all_edges(i, 1)) <= tol
            j = j + 1;
            chans_seen = union(chans_seen, all_edges(j, 2));
        end
        if numel(chans_seen) >= nChan
            rising_edges(end+1) = round(mean(all_edges(i:j, 1))); %#ok<AGROW>
        end
        i = j + 1;
    end

    if isempty(rising_edges)
        t_zero = [];
        abort_markers = [];
        return
    end

    t_zero = rising_edges(1);
    abort_markers = rising_edges(2:end);
end


function meta = buildTrialMeta(MasterData, t)
    trialNum   = MasterData(t).TrialNum;
    taskType   = MasterData(t).TaskType;
    direction  = MasterData(t).Direction;
    targetDeg  = MasterData(t).TargetDeg;
    targetDist = MasterData(t).TargetDist;

    switch taskType
        case 'I'
            taskWord = 'Imagine';
        case 'P'
            taskWord = 'Physical';
        otherwise
            error('Unrecognized TaskType ''%s'' for trial %d.', taskType, trialNum);
    end

    switch direction
        case 'L'
            dirWord = 'Left';
        case 'R'
            dirWord = 'Right';
        otherwise
            error('Unrecognized Direction ''%s'' for trial %d.', direction, trialNum);
    end

    if targetDeg >= 0 && targetDeg < 90
        quadrant = 'Q1';
    elseif targetDeg >= 90 && targetDeg < 180
        quadrant = 'Q2';
    elseif targetDeg >= 180 && targetDeg < 270
        quadrant = 'Q3';
    elseif targetDeg >= 270 && targetDeg < 360
        quadrant = 'Q4';
    else
        error('TargetDeg %g out of [0,360) range for trial %d.', targetDeg, trialNum);
    end

    meta.TrialNum  = trialNum;
    meta.TaskType  = taskWord;
    meta.Direction = dirWord;
    meta.Quadrant  = quadrant;
    meta.Distance  = targetDist;
end
