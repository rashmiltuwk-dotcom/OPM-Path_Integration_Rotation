%% MOVEMENT ACCURACY EXPERIMENT
% 64 runs with button press (press '1' to start)
% Escape to quit, 'r' to redo trial
% Tracks: accepted, aborted, displacement

clear all; close all;

% Initialize OptiTrack
OptiTrackBridge.Connect('SubjectTest');

% Screen setup
screenNumber = max(Screen('Screens'));
[win, rect] = Screen('OpenWindow', screenNumber, 0);
Screen('TextSize', win, 40);
HideCursor();

try
    %% Experiment parameters
    numRuns = 64;
    masterTrace = struct();
    
    % Start continuous tracking for entire session
    OptiTrackBridge.StartContinuousCollection();
    
    %% Main trial loop
    runNum = 0;
    
    while runNum < numRuns
        runNum = runNum + 1;
        
        % Trial instruction screen
        DrawFormattedText(win, sprintf('Trial %d / %d\n\nPress 1 when ready to start', runNum, numRuns), ...
            'center', 'center', [255 255 255]);
        Screen('Flip', win);
        
        % Wait for '1' key press
        waitForOne = true;
        while waitForOne
            [kd, ~, kc] = KbCheck;
            if kd && kc(KbName('ESCAPE'))
                error('User Quit');
            end
            if kd && kc(KbName('1'))
                WaitSecs(0.3);
                waitForOne = false;
            end
            WaitSecs(0.01);
        end
        
        % Log trial start
        OptiTrackBridge.startEvent(runNum, 'TrialStart');
        
        % Record until person presses space
        try
            [~, ~, headTrace, torsoTrace] = OptiTrackBridge.RecordUntilKey(1, 2, 'space', win);
            
            % Store trial in master trace
            trialName = sprintf('Trial_%d', runNum);
            masterTrace.(trialName).headTrace = headTrace;
            masterTrace.(trialName).torsoTrace = torsoTrace;
            
            % Log trial end
            OptiTrackBridge.stopEvent(runNum, 'TrialEnd');
            
            % Display completion
            DrawFormattedText(win, sprintf('Trial %d Complete', runNum), 'center', 'center', [0 255 0]);
            Screen('Flip', win);
            WaitSecs(1.0);
            
        catch ME
            if strcmp(ME.message, 'Redo_Trial')
                DrawFormattedText(win, 'Redo this trial', 'center', 'center', [255 255 0]);
                Screen('Flip', win);
                WaitSecs(1.0);
                runNum = runNum - 1;  % Decrement to retry
                continue;
            else
                rethrow(ME);
            end
        end
    end
    
    %% Summary
    DrawFormattedText(win, 'Experiment Complete!', 'center', 'center', [0 255 255]);
    Screen('Flip', win);
    WaitSecs(2.0);
    
    %% Save data
    timestamp = datetime('now', 'Format', 'yyyyMMdd_HHmmss');
    filename = sprintf('test_data_different_positions_%s.mat', timestamp);
    
    OptiTrackBridge.StopContinuousCollection();
    OptiTrackBridge.SaveContinuous(filename);
    
    save(filename, 'masterTrace', '-append');
    fprintf('Data saved to: %s\n', filename);
    
catch ME
    fprintf('Error: %s\n', ME.message);
    ShowCursor();
    Screen('CloseAll');
    OptiTrackBridge.Disconnect();
    rethrow(ME);
end

%% Cleanup
ShowCursor();
Screen('CloseAll');
OptiTrackBridge.Disconnect();
fprintf('Session complete.\n');
