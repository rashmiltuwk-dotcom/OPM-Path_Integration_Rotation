%% ============================================================
%  AUTOMATED FOLDER MERGE
%  Automatically finds and combines all 'MasterData' files 
%  within a specific folder.
%
%  NOTE: Blocks run individually during data collection, and are hence saved individually. 
%  Run this script to consolidate them into one MasterData 
%  struct array for combined analysis.
%% ============================================================

% 1. Point to the folder containing your data files
folderPath = uigetdir(pwd, 'Select the folder containing MasterData files');

if folderPath == 0
    disp('No folder selected. Operation canceled.');
    return;
end

% 2. Get a list of all .mat files in that folder
fileList = dir(fullfile(folderPath, '*MasterData.mat'));

if isempty(fileList)
    error('No files ending in "_MasterData.mat" found in the selected folder.');
end

% 3. Initialize the aggregated array
MasterData = [];

% 4. Loop through every file found in the folder
for i = 1:length(fileList)
    fullFileName = fullfile(fileList(i).folder, fileList(i).name);
    fprintf('Loading: %s...\n', fileList(i).name);
    
    data = load(fullFileName);
    
    if isfield(data, 'MasterData')
        MasterData = [MasterData, data.MasterData];
        fprintf('  Stacked %d trials.\n', numel(data.MasterData));
    else
        warning('File %s does not contain "MasterData". Skipping.', fileList(i).name);
    end
end

% 5. Save the combined results
save('Combined_Analysis_MasterData.mat', 'MasterData', '-v7.3');

fprintf('\nSuccess! Merged %d files from folder.\n', length(fileList));
fprintf('Total Trials available: %d\n', numel(MasterData));
fprintf('Saved as "Combined_Analysis_MasterData.mat".\n');
