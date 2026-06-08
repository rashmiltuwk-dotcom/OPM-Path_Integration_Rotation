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
    error('No files ending in "*MasterData.mat" found in the selected folder.');
end

% 3. Initialize the aggregated array
MasterData = [];
totalTrials = 0;
filesLoaded = 0;
filesSkipped = 0;

fprintf('Starting merge of %d files...\n\n', length(fileList));

% 4. Loop through every file found in the folder
for i = 1:length(fileList)
    fullFileName = fullfile(fileList(i).folder, fileList(i).name);
    fprintf('[%d/%d] Loading: %s...', i, length(fileList), fileList(i).name);
    
    try
        data = load(fullFileName);
        
        if ~isfield(data, 'MasterData')
            fprintf(' SKIPPED (no MasterData field)\n');
            filesSkipped = filesSkipped + 1;
            continue;
        end
        
        currentData = data.MasterData;
        
        % Check for empty data
        if isempty(currentData)
            fprintf(' SKIPPED (empty)\n');
            filesSkipped = filesSkipped + 1;
            continue;
        end
        
        % Concatenate (works even if MasterData is initially empty)
        if isempty(MasterData)
            MasterData = currentData;
        else
            % Verify field compatibility
            if ~isequal(fieldnames(MasterData(1)), fieldnames(currentData(1)))
                fprintf(' ERROR (field mismatch - skipping)\n');
                filesSkipped = filesSkipped + 1;
                continue;
            end
            MasterData = [MasterData, currentData];
        end
        
        fprintf(' OK (%d trials)\n', numel(currentData));
        filesLoaded = filesLoaded + 1;
        totalTrials = totalTrials + numel(currentData);
        
    catch ME
        fprintf(' ERROR (%s)\n', ME.message);
        filesSkipped = filesSkipped + 1;
    end
end

% 5. Deduplicate by TrialNum (optional - keep only unique trials)
if isfield(MasterData, 'TrialNum') && ~isempty(MasterData)
    [~, uniqueIdx] = unique([MasterData.TrialNum], 'last');
    uniqueIdx = sort(uniqueIdx);
    duplicatesRemoved = numel(MasterData) - numel(uniqueIdx);
    if duplicatesRemoved > 0
        fprintf('\nRemoving %d duplicate trials...\n', duplicatesRemoved);
        MasterData = MasterData(uniqueIdx);
    end
end

% 6. Save the combined results
if isempty(MasterData)
    warning('No data was loaded. File not saved.');
else
    save('Combined_Analysis_MasterData.mat', 'MasterData', '-v7.3');
    fprintf('\n✓ Success!\n');
    fprintf('  Files processed: %d loaded, %d skipped\n', filesLoaded, filesSkipped);
    fprintf('  Total trials: %d\n', numel(MasterData));
    fprintf('  Saved as: Combined_Analysis_MasterData.mat\n');
end
