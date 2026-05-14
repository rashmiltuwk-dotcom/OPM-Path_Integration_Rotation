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


%% 2. The "All-In-One" Epoch & Baseline Step
disp('Running automated trigger detection, epoching, and baseline correction...');

S = [];
S.D = D1;                     % Use the file we just created
S.timewin = [-200 3000];      % Cut from -200ms to +3000ms
S.bc = 1;                     % 1 = Yes, apply baseline correction automatically

% List the trigger channels you want to scan
S.triggerChannels = {'T2', 'T3', 'T6', 'T7', 'T8', 'T9', 'T10'};

% List the names you want to give the trials (must match the order above)
S.condLabels = {'Stim_T2', 'Stim_T3', 'Stim_T6', 'Stim_T7', 'Stim_T8', 'Stim_T9', 'Stim_T10'};

% CRITICAL FIX: Set threshold to 0.05 to catch your 0.1V pulses
S.thresh = 0.05; 

% Run the wrapper function
[epoch_bc_D] = spm_opm_epoch_trigger(S);


%% 3. Finish
disp('SUCCESS! Preprocessing complete.');
disp(['Final epoched and baseline-corrected file saved as: ', epoch_bc_D.fname]);
