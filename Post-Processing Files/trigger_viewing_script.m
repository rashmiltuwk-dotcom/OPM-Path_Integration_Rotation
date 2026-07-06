%% HouseKeeping
clearvars % MATLAB built-in function: Clears variables from the workspace.
close all % MATLAB built-in function: Closes all open figure windows.
pl=1;
 
% Change to your path format
addpath('C:/Users/spaceandmem/rashmil_opm/spm/') % MATLAB built-in function: Adds the specified folder to the search path.
addpath('C:/Users/spaceandmem/rashmil_opm/data_dump/') 
spm('defaults','EEG') % External function (SPM12): Initializes SPM defaults specifically for M/EEG data.
 
cd('C:/Users/spaceandmem/rashmil_opm/data_dump/'); % MATLAB built-in function: Changes the current working directory.
S= [];
S.data = 'Imagniation-run-002_30-06-2026_16-59-42_array1.lvm';
D1 = spm_opm_create(S); % External function (SPM12): Reads OPM data and creates an SPM M/EEG object.
 
figure() % MATLAB built-in function: Opens a new blank figure window.
channels = [5, 8, 6, 9, 2, 10, 7, 3];

labels = {'Close Eyes', 'Stationary', 'Physical Walk', 'Encoding Rot', ...
          'Imagine Walk', 'Response Rot', 'Open Eyes', 'Master Sync'};
          
colors = lines(length(channels)); % MATLAB built-in functions (lines, length): 'length' gets array size, 'lines' generates a colormap matrix.

for k = 1:length(channels) % MATLAB built-in function (length): Used here to determine loop iterations.
    i = channels(k);
    label = "T" + i;
    
    subplot(length(channels), 1, k) % MATLAB built-in function: Divides the figure into a grid and creates axes in the k-th position.
    
    % indchannel is an External function/method (SPM12): Finds the numeric index of a specific channel label within the SPM M/EEG object (D1).
    signal = D1(indchannel(D1, label),:,1); 
    
    plot(D1.time, signal, 'Color', colors(k,:)) % MATLAB built-in function: Plots the 2D data. (Note: D1.time accesses a property of the external SPM object).
    title(labels{k}) % MATLAB built-in function: Adds a text title to the current subplot.
    
    if k < length(channels) % MATLAB built-in function (length).
        set(gca, 'XTickLabel', []) % MATLAB built-in functions (set, gca): 'gca' gets the current axes, 'set' modifies its properties (hiding the x-axis labels).
    else
        xlabel('Time (s)') % MATLAB built-in function: Adds a label to the x-axis for the final subplot.
    end
end
