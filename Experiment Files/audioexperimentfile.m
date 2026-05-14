function runExperimentTest
%(custom) allows to create personal workspace, will enable the use of storing audio
%and utilising it in the future

% ---------------------------------------------------------

% 1. INITIAL SETUP

% ---------------------------------------------------------

clear all; close all; sca;

Screen('Preference', 'SkipSyncTests', 1); % Bypasses timing crashes during testing

%[MATLAB] Wipe memory & close windows, ensures something else is not playing;
% [PTB] shut down screens, different for PTB bc we use ptb to display on
% screens to prevent delay

% {{{{ OPTITRACK CONNECT }}}
connected = OptiTrackBridge.Connect(); % [OptiTrack] Initialize connection to the cameras

if ~connected % [MATLAB] If the connection fails...

    warning('OptiTrack NOT detected. Running in Dummy Mode?'); % [MATLAB] Print a warning

end

% {{{{ Psychtoolbox Setup }}}

% --- PTB SETUP (Psychtoolbox) ---
% Standard: For real data collection, 'SkipSyncTests' MUST be 0. 
% This ensures Psychtoolbox can guarantee millisecond timing accuracy.
Screen('Preference', 'SkipSyncTests', 0); 

% Standard: 'PsychDefaultSetup(2)' is the modern standard; it sets up 
% normalized coordinates and advanced color handling automatically.
PsychDefaultSetup(2); 

% Standard: Fixes keyboard ID differences between Windows, Mac, and Linux.
KbName('UnifyKeyNames'); 

% Standard: Wakes up the high-priority audio driver to prevent 
% "lag" the first time a sound is played.
InitializePsychSound(1);

% --- INPUT DIALOG (Participant Metadata) ---

prompt = {'Participant ID:'}; 
definput = {'001'};
answer = inputdlg(prompt, 'Task Setup', [1 45], definput);

if isempty(answer), return; end % Safety exit

subjID  = answer{1};


% --- FILE & FOLDER MANAGEMENT ---

timeStr = datestr(now, 'yyyy-mm-dd_HHMMSS');

% 1. The Summary File (The "Manager" Spreadsheet)
% Format: P001_2026-03-04_120000_Results.csv
dataFile = sprintf('P%s_%s_Results.csv', subjID, timeStr);

% 2. The Trace Folder (The "Library" for raw motion)
% Format: P001_Traces
traceFolder = sprintf('P%s_%s_Traces', subjID, timeStr);

% Create the folder if it doesn't exist.
% Standard: This prevents a crash when we try to save raw data later.
if ~exist(traceFolder, 'dir')
    mkdir(traceFolder); 
end

% 3. TriggerLogger

% '378' is the standard Hexadecimal address for the Parallel (LPT) port.
% hex2dec converts this to decimal 888 so MATLAB drivers can "talk" to the pin.

try
    % Initialize the custom TriggerLogger class. 
    % This creates a digital record of every pulse sent to the MEG room.
    TL = TriggerLogger(subjID); 
catch
    % SAFETY: If the LPT cable isn't plugged in (e.g., testing at home),
    % we set TL to empty so the script doesn't crash.
    warning('MEG Trigger hardware not detected. Switching to Dummy Mode.');
    TL = []; 
end
% ---------------------------------------------------------

% 2. SETUP UP AUDIO AND SCREEN

% ---------------------------------------------------------


% WINDOW & AUDIO LOAD


% --- EMERGENCY OVERRIDE ---
sca; 
Screen('Preference', 'SkipSyncTests', 1); 
Screen('Preference', 'VisualDebugLevel', 1); % Reduces internal PTB chatter

% --- SCREEN SELECTION ---
% Your logs show [0 1 2]. Let's try 2 for the Projector.
% If 2 is the wrong screen, change this to 1.
screenNumber = 1; 

try
    % Open the window
    [win, winRect] = Screen('OpenWindow', screenNumber, [0 0 0]);
catch
    fprintf('Screen %d failed. Falling back to Screen 0.\n', screenNumber);
    [win, winRect] = Screen('OpenWindow', 0, [0 0 0]);
end

% Set text properties
white = WhiteIndex(win);
Screen('TextFont', win, 'Arial');
Screen('TextSize', win, 40);

% [PTB] Open the PsychPortAudio device.
% Standard: Parameters explained:
% [] - Use default audio device.
% 1  - Mode 1: Playback only (Low Latency).
% 1  - Latency Class 1: Tells the PC to give audio 100% priority.
% 48000 - Sample Rate: High-definition standard.
% 2  3113- Channels: Stereo output.
pahandle = PsychPortAudio('Open', [], 1, 1, 48000, 2);

% [MATLAB] Define a cell array of audio filenames needed for the task.
files = {'CloseE','OpenE','Return', 'Restart' ,'Rank','ImagineS','StartW','stop',...
         'ImagineW','RotateL','RotateR','ImagineRo','PhysicalRo'};

% [MATLAB] Loop through and load each audio file into memory.
% NOTE THAT THIS HAS BEEN PRACTICED TO PREVENT AUDIO GLITCHES
%THE RESAMPLING IS TO FIT THE SAMPLING OF THE SPEAKERS IN THE OPM-MEG ROOM

for i = 1:numel(files)
    fname = [files{i} '.wav']; 
    
    if exist(fname, 'file')
        [d, fs] = audioread(fname); % Load the sound.
        
        if fs ~= 48000
            d = resample(d, 48000, fs); 
        end
        
        % Standard: Force Mono sounds to Stereo by duplicating the track.
        % This ensures the participant hears the voice in both ears equally.
        if size(d,2) < 2
            d = [d d]; 
        end
        
        % [PTB] Store the sound data transposed (PsychPortAudio requirement).
        audioData.(files{i}) = d'; 
    else
        % Standard: Defensive programming. If a file is missing, we create 
        % a "silent" buffer so the experiment doesn't crash mid-session.
        warning('Audio file %s not found. Using silence.', fname);
        audioData.(files{i}) = zeros(2, 48000); 
    end
end

% ---------------------------------------------------------
% 3. TASK DESIGN 
% ---------------------------------------------------------


% Standard: Define the Map HERE. 
% This is your "Look-up Table." It never changes during the experiment.
angleMap = containers.Map({'Q1','Q2','Q3','Q4'}, [60, 120, 240, 300]);
distance =  containers.Map({'D1','D2','D3','D4'}, [1.0, 1.5, 2.0, 2.5]);

% [MATLAB] Define the 4 basic blocks (Chunks)
% --- LEFT POSITION (LPos) CHUNKS ---
% Columns: 1=Position(LPos/RPos), 2=Rotation(L/R), 3=Modality(I/P), 4=D-Factor, 5=Q-Factor

% [MATLAB] Define the 8 basic blocks (Chunks) WITH POSITIONS MAPPED
% Perfectly counterbalanced using a Graeco-Latin Square.

% BASE CHUNKS (Set A)
chunk1 = {'LPos', 'L', 'I', 'D1', 'Q1'; 
          'RPos', 'R', 'I', 'D2', 'Q3'; 
          'LPos', 'R', 'P', 'D3', 'Q4'; 
          'RPos', 'L', 'P', 'D4', 'Q2'};

chunk2 = {'LPos', 'L', 'I', 'D2', 'Q4'; 
          'RPos', 'R', 'I', 'D1', 'Q2'; 
          'LPos', 'R', 'P', 'D4', 'Q1'; 
          'RPos', 'L', 'P', 'D3', 'Q3'};

chunk3 = {'LPos', 'L', 'I', 'D3', 'Q2'; 
          'RPos', 'R', 'I', 'D4', 'Q4'; 
          'LPos', 'R', 'P', 'D1', 'Q3'; 
          'RPos', 'L', 'P', 'D2', 'Q1'};

chunk4 = {'LPos', 'L', 'I', 'D4', 'Q3'; 
          'RPos', 'R', 'I', 'D3', 'Q1'; 
          'LPos', 'R', 'P', 'D2', 'Q2'; 
          'RPos', 'L', 'P', 'D1', 'Q4'};

% --- INVERTED CHUNKS (Set B: Exact opposite positions) ---
chunk5 = {'RPos', 'L', 'I', 'D1', 'Q1'; 
          'LPos', 'R', 'I', 'D2', 'Q3'; 
          'RPos', 'R', 'P', 'D3', 'Q4'; 
          'LPos', 'L', 'P', 'D4', 'Q2'};

chunk6 = {'RPos', 'L', 'I', 'D2', 'Q4'; 
          'LPos', 'R', 'I', 'D1', 'Q2'; 
          'RPos', 'R', 'P', 'D4', 'Q1'; 
          'LPos', 'L', 'P', 'D3', 'Q3'};

chunk7 = {'RPos', 'L', 'I', 'D3', 'Q2'; 
          'LPos', 'R', 'I', 'D4', 'Q4'; 
          'RPos', 'R', 'P', 'D1', 'Q3'; 
          'LPos', 'L', 'P', 'D2', 'Q1'};

chunk8 = {'RPos', 'L', 'I', 'D4', 'Q3'; 
          'LPos', 'R', 'I', 'D3', 'Q1'; 
          'RPos', 'R', 'P', 'D2', 'Q2'; 
          'LPos', 'L', 'P', 'D1', 'Q4'};

% [MATLAB] Organize the chunks into a "Cell of Cells" for easy indexing
allChunks = {chunk1, chunk2, chunk3, chunk4, chunk5, chunk6, chunk7, chunk8};

% [MATLAB] Determine the starting sequence using Participant ID
pID_num = str2double(subjID);

% Using mod(pID_num - 1, 6) + 1 ensures exact wrapping. 
% IDs 1-6 get Orders 1-6. ID 7 wraps back to Order 1, ID 12 gets Order 6, etc.
orderChoice = mod(pID_num - 1, 6) + 1;


% [MATLAB] Define the 6 explicit 16-trial sequences 
% Using Chunks 1-4 (Set A) and 5-8 (Set B) to ensure 32 Left / 32 Right trials.
sequences = [
    1, 2, 6, 5,   3, 4, 8, 7,   5, 6, 2, 1,   7, 8, 4, 3;  % Order 1 (P1, P7...)
    2, 3, 7, 6,   4, 1, 5, 8,   6, 7, 3, 2,   8, 5, 1, 4;  % Order 2 (P2, P8...)
    3, 4, 8, 7,   1, 2, 6, 5,   7, 8, 4, 3,   5, 6, 2, 1;  % Order 3 (P3, P9...)
    4, 1, 5, 8,   2, 3, 7, 6,   8, 5, 1, 4,   6, 7, 3, 2;  % Order 4 (P4, P10...)
    5, 6, 2, 1,   7, 8, 4, 3,   1, 2, 6, 5,   3, 4, 8, 7;  % Order 5 (P5, P11...)
    6, 7, 3, 2,   8, 5, 1, 4,   2, 3, 7, 6,   4, 1, 5, 8   % Order 6 (P6, P12...)
];

% [MATLAB] Extract the specific 16-chunk sequence for THIS participant
mySeq = sequences(orderChoice, :);

% [MATLAB] Build the full 16-trial schedule
raw_schedule = [ 
    % Block 1
    allChunks{mySeq(1)}; allChunks{mySeq(2)}; allChunks{mySeq(3)}; allChunks{mySeq(4)}; ...
    % Block 2
    allChunks{mySeq(5)}; allChunks{mySeq(6)}; allChunks{mySeq(7)}; allChunks{mySeq(8)}; ...
    % Block 3
    allChunks{mySeq(9)}; allChunks{mySeq(10)}; allChunks{mySeq(11)}; allChunks{mySeq(12)}; ...
    % Block 4
    allChunks{mySeq(13)}; allChunks{mySeq(14)}; allChunks{mySeq(15)}; allChunks{mySeq(16)}
];

% Standard: Assign to trials variable
trials = raw_schedule;

% Standard: Initialize the results table with headers BEFORE the loop starts.
results = table();

% ---------------------------------------------------------
% 4. MAIN LOOP (Trial Execution)
% ---------------------------------------------------------

    try % [MATLAB] Safety "Net": If anything fails, it jumps to the catch block at the end.

    audioTestComplete = false;
    while ~audioTestComplete
        % Display instructions on the screen
        DrawFormattedText(win, 'AUDIO TEST\n\nPlaying test sound...\n\nPress SPACE to start the study.\nPress "1!" to hear the audio again.', 'center', 'center', white);
        Screen('Flip', win);
        
        % Play the audio test sound (blocking so it finishes before they can skip)
        play_sound_blocking(pahandle, audioData.AudioTest);
        
        % Wait for their response
        KbReleaseWait;
        while true
            [kd, ~, kc] = KbCheck;
            if kd && kc(KbName('space'))
                audioTestComplete = true; % Exits the audio test loop
                break;
            elseif kd && kc(KbName('1!'))
                break; % Breaks the inner wait loop, causing the outer loop to replay the audio
            elseif kd && kc(KbName('ESCAPE'))
                error('User Quit');
            end
            WaitSecs(0.01); % CPU relief
        end
    end

    % --- THE "READY" SCREEN ---
    % Standard: Provide a clear starting point for the participant.
    DrawFormattedText(win, 'The experiment is starting.\n\nPlease stand still.\n\nPress SPACE to begin.', ...
        'center', 'center', white);
    Screen('Flip', win); % Push the text to the actual monitor
    wait_key('space');   % Custom function: wait for keyboard input

% --- BEGIN TRIAL ITERATION ---
    for t = 1:8 % This will run exactly 8 times
        
        trialAccepted = false; 
        attemptNum = 1; % Tracks how many times they have tried THIS trial      

        while ~trialAccepted 
            
            % 1. CRITICAL: PRE-ALLOCATE VARIABLES FIRST
            [walkDistTorso, walkDistHead, walkTime, startHead, startTorso, actualHead, actualTorso, turnTime, ...
             actHead, actTorso, rt_Rot, imagineWalkTime, encodeTurnAmount,encodeTorsoTurn, prodTurnAmount, prodTorsoTurn, ...
             encodeDriftHead, encodeDriftTorso, prodDriftHead, prodDriftTorso] = deal(NaN); % <-- ADDED DRIFT VARS
            rank = ''; % Reset rank
            
            [PhysicallyWalkHeadTrace, TorsoPhysicallyWalkHeadTrace, ...
            EncodingRotateHeadTrace, EncodingRotateTorsoTrace, ...
            ResponseRotationHeadTrace, ResponseRotationTorsoTrace, ...
            ImagineWalkingHeadTrace, ImagineWalkingTorsoTrace, ...
            PassiveEncodeHeadTrace, PassiveEncodeTorsoTrace, ...   % <-- ADDED
            PassiveProdHeadTrace, PassiveProdTorsoTrace] = deal([]); % <-- ADDED
            
            try % --- THE RIPCORD STARTS HERE ---
                
                
                % ---------------------------------------------------------
                % [MATLAB] EXTRACT TRIAL METADATA
                % ---------------------------------------------------------
                dirCode    = trials{t,1}; % 'L' or 'R'
                typeCode   = trials{t,2}; % 'I' (Imagine) or 'P' (Physical)
                distCode   = trials{t,3}; % 'D1' to 'D4'
                qCode      = trials{t,4}; % 'Q1' to 'Q4'
                participantPosition = trials{t,5}; %'LPos' (Left Side) or 'RPos'

                targetDeg  = angleMap(qCode); % Look up the degrees (60, 120, etc.)
                targetDist = distance(distCode); % Look up the distance (1.0, 1.5, etc.)

                % ---------------------------------------------------------
                % DYNAMIC COUNTERBALANCING (Position, Direction, Task Type)
                % ---------------------------------------------------------
                % Using pID_num (numeric) instead of subjID (string)

% --- UPDATED VISUAL CUE ---
% Translate LPos/RPos into readable text for the screen
if strcmp(participantPosition, 'LPos')
    displayPosText = 'LEFT SIDE';
else
    displayPosText = 'RIGHT SIDE';
end

% This displays the Target Distance and the required Room Position
line1 = sprintf('TRIAL %d of 8', t, size(trials, 1));
line2 = sprintf('POSITION: %s', displayPosText); % Uses the translated text
line3 = sprintf('WALK DISTANCE: %.1f m', targetDist);
line4 = '\nResearcher: Press SPACE to begin.';

DrawFormattedText(win, [line1 '\n\n' line2 '\n' line3 '\n\n' line4], 'center', 'center', white);
Screen('Flip', win);


% Pause for researcher
wait_key('space');   
Screen('Flip', win); 
WaitSecs(0.5);
                
                % ---------------------------------------------------------
                % EVENT 1: CLOSE EYES
                % ---------------------------------------------------------
                % [Trigger] Code 1: Instruction to close eyes
                if ~isempty(TL), TL.startEvent(1, t, 'CloseEyes'); end
                
                % [Audio] "Close your eyes" (Blocking: wait for sound to finish)
                play_sound_blocking(pahandle, audioData.CloseE);
                
                if ~isempty(TL), TL.stopEvent(1, t, 'CloseEyes'); end

                % ---------------------------------------------------------
                % THREE SECOND STATIONARY TIME PERIOD
                % ---------------------------------------------------------
                
                % Trigger Channel 2 is used to mark this stationary epoch in the MEG.
                
                if ~isempty(TL), TL.startEvent(2, t, 'Stationary'); end
                
                WaitSecs(3.0); 
                
                if ~isempty(TL), TL.stopEvent(2, t, 'Stationary'); end
                
                % ---------------------------------------------------------
                % EVENT 2: PHYSICAL WALK 
                % ---------------------------------------------------------

                if ~isempty(TL), TL.startEvent(3, t, 'PhysWalk'); end
                
                % 1. Tell them to walk (Blocking: wait for the audio to finish completely)
                play_sound_blocking(pahandle, audioData.StartW); 
                
                % 2. START THE TIMER: The exact millisecond the audio ends
                walkStartTime = GetSecs(); 
                
                % 3. Track them until they hit the (0,0) coordinate
                % UPDATED: Now capturing 'walkTraces' alongside distance
                [walkDistTorso, walkDistHead, PhysicallyWalkHeadTrace, TorsoPhysicallyWalkHeadTrace] = OptiTrackBridge.WaitForOrigin(win, 0.50);
                
                % 4. STOP THE TIMER: Record exactly how long it took
                walkTime = GetSecs() - walkStartTime; 
                
                % 5. Immediately tell them to stop
                play_sound_blocking(pahandle, audioData.stop); 
                
                if ~isempty(TL), TL.stopEvent(3, t, 'PhysWalk'); end

                % Keep the info on screen during the stationary period 
                % so they can process it while standing still.

                % ---------------------------------------------------------
                % ENSURE CONTINUOUS STATIONARY PERIOD AT (0,0,0)
                % ---------------------------------------------------------
                
                % ... (Your Stationary Loop code follows here) ...

                % --- REINSTATED ORIGINAL LOGIC (CLEANED) ---
                centerThreshold = 0.35;  
                requiredTime = 0.5;      
                isWarningOnScreen = false; 

                stationaryStartTime = GetSecs(); 

                while (GetSecs() - stationaryStartTime) < requiredTime
                    % 1. Safety Exit (Always needed in a while loop)
                    [kd, ~, kc] = KbCheck;
                    if kd && kc(KbName('ESCAPE')), error('User Quit'); end
                    
                    % ---> THE RIPCORD CHECK ADDED HERE <---
                    if kd && kc(KbName('r')), error('Redo_Trial'); end 

                    % 2. Get Position as a single array (Prevents "Too Many Arguments" error)
                    [~, currTorsoPos, ~, ~] = OptiTrackBridge.GetOpti();
                    currPos = currTorsoPos; % To keep your existing logic working
                    
                    % 3. Check for valid data (Prevents math errors on NaNs)
                    if any(isnan(currPos))
                        WaitSecs(0.01); 
                        continue; 
                    end

                    % 4. Calculate distance (X and Z only for floor distance)
                    distFromCenter = sqrt(currPos(1)^2 + currPos(3)^2); 
                    
                    if distFromCenter > centerThreshold
                        % Reset the timer because they moved
                        stationaryStartTime = GetSecs(); 
                        
                        if ~isWarningOnScreen
                            DrawFormattedText(win, 'WARN PARTICIPANT: Please return to the center.', 'center', 'center', white);
                            Screen('Flip', win); 
                            isWarningOnScreen = true; 
                        end
                    else
                        % They are back in range
                        if isWarningOnScreen
                            Screen('Flip', win); % Clear warning back to black
                            isWarningOnScreen = false;
                        end
                    end
                    
                    % 5. The "Brake" (Prevents the hard crash/freeze)
                    Screen('Flip', win)
                end
                % --------------------------------------------
                    
                % ---------------------------------------------------------
                % NEW: DISPLAY UPCOMING ROTATION INFO
                % ---------------------------------------------------------
                % Determine direction text for the visual cue
                if strcmp(dirCode, 'L')
                    dirText = 'LEFT';
                    txtColor = [0 200 255]; % Light Blue for Left
                elseif strcmp(dirCode, 'R')
                    dirText = 'RIGHT';
                    txtColor = [255, 150, 0]; % Orange/Yellow for Right
                end

                % Display the info immediately after the walk ends
                infoMsg = sprintf('WALK COMPLETE\n\nNext Rotation: %s\nAmount: %.1f Degrees', dirText, targetDeg);
                DrawFormattedText(win, infoMsg, 'center', 'center', txtColor);
                Screen('Flip', win);

                % ---------------------------------------------------------
                % THREE SECOND STATIONARY TIME PERIOD
                % ---------------------------------------------------------
               
                % Trigger Channel 2 is used to mark this stationary epoch in the MEG.
                
                if ~isempty(TL), TL.startEvent(2, t, 'Stationary'); end
                
                WaitSecs(3.0); 
                
                if ~isempty(TL), TL.stopEvent(2, t, 'Stationary'); end

                % ---------------------------------------------------------
                % EVENT 3: PHYSICAL ROTATION (Encoding)
                % ---------------------------------------------------------
                % Start MEG Trigger for Encoding
                if ~isempty(TL), TL.startEvent(4, t, 'PhysRotateEncoding'); end
                
                % 1. Determine direction and play audio
                
                if strcmpi(strtrim(dirCode), 'L')
                    wav = audioData.RotateL;
                elseif strcmpi(strtrim(dirCode), 'R')
                    wav = audioData.RotateR;
                else

                end

                play_sound_blocking(pahandle, wav);
                
                % 2. THE START CLICK
                % Record the exact time the participant is cleared to start moving
                startTime = GetSecs(); 
                
                % 3. DUAL TRACKING: Head and Torso
                % [UPDATED] Catching startHead and startTorso
                [startHead, startTorso, actualHead, actualTorso, EncodingRotateHeadTrace, EncodingRotateTorsoTrace] = ...
                    OptiTrackBridge.WaitForRotationDual(targetDeg, win, dirCode);
                
                % 4. THE STOP CLICK
                % Calculate total time from "Go" to "Target Hit"
                turnTime = GetSecs() - startTime; 
                
                % 5. END TRIGGER & STOP AUDIO (Immediate)
                if ~isempty(TL), TL.stopEvent(4, t, 'PhysRotateEncoding'); end
                
                % Immediate feedback: No delay between target hit and "Stop" sound
                play_sound(pahandle, audioData.stop);

                captureDuration = 0.5; % Record for 0.5 seconds after they stop
                [PassiveEncodeHeadTrace, PassiveEncodeTorsoTrace] = OptiTrackBridge.PassiveTrack(captureDuration);
                
                if ~isempty(PassiveEncodeTorsoTrace.yaw)
                    % Calculate shortest path drift (handles 360-degree wrap around)
                    initT = PassiveEncodeTorsoTrace.yaw(1); finT = PassiveEncodeTorsoTrace.yaw(end);
                    encodeDriftTorso = mod((finT - initT) + 180, 360) - 180;
                    
                    initH = PassiveEncodeHeadTrace.yaw(1); finH = PassiveEncodeHeadTrace.yaw(end);
                    encodeDriftHead = mod((finH - initH) + 180, 360) - 180;
                else
                    encodeDriftTorso = 0; encodeDriftHead = 0;
                end 

                % ---------------------------------------------------------
                % EVENT 4: ROTATION TASK (Physical/Imagined)
                % ---------------------------------------------------------

                if ~isempty(TL), TL.startEvent(5, t, 'RotationProduction'); end
                
                % 1. Play the Instruction (Imagine or Physical)
                if strcmp(typeCode, 'I')
                    play_sound(pahandle, audioData.ImagineRo);
                else
                    play_sound(pahandle, audioData.PhysicalRo);
                end
                
                % 2. START THE HIGH-RES CLOCK
                % This marks the "Go" signal for the participant
                startTime = GetSecs(); 

                % 3. DUAL TRACKING: Head and Torso (Continuous Recording)
                % Instead of 'WaitForRotation' (which stops at a target), we use 
                % 'RecordUntilKey', which records until they hit '1!'.
                [actHead, actTorso, ResponseRotationHeadTrace, ResponseRotationTorsoTrace] = ...
                    OptiTrackBridge.RecordUntilKey('1!', win);
                
                % 4. CALCULATE TASK DURATION (TaskTime)
                % This is the time from the audio ending to the button press '1!'
                taskTime = GetSecs() - startTime; 
                rt_Rot = taskTime; % Syncing with your existing variable name

                % 5. END TRIGGER
                if ~isempty(TL), TL.stopEvent(5, t, 'RotationProduction'); end
                
                [PassiveProdHeadTrace, PassiveProdTorsoTrace] = OptiTrackBridge.PassiveTrack(captureDuration);
                
                if ~isempty(PassiveProdTorsoTrace.yaw)
                    initT = PassiveProdTorsoTrace.yaw(1); finT = PassiveProdTorsoTrace.yaw(end);
                    prodDriftTorso = mod((finT - initT) + 180, 360) - 180;
                    
                    initH = PassiveProdHeadTrace.yaw(1); finH = PassiveProdHeadTrace.yaw(end);
                    prodDriftHead = mod((finH - initH) + 180, 360) - 180;
                else
                    prodDriftTorso = 0; prodDriftHead = 0;
                end

                % ---------------------------------------------------------
                % EVENT 5: Imagine Walk
                % ---------------------------------------------------------

                if ~isempty(TL), TL.startEvent(6, t, 'ImagineWalk'); end
                
                % 1. Play the "Imagine Walking" audio
                play_sound(pahandle, audioData.ImagineW);
                
                % 2. THE START CLICK
                % We grab the time the moment the participant is told to start imagining.
                startTimeImagine = GetSecs(); 
                
                % 3. THE "STOP" BUTTON (Key '1!')

                [~, ~, ImagineWalkingHeadTrace, ImagineWalkingTorsoTrace] = ...
                    OptiTrackBridge.RecordUntilKey('1!', win);
                
                % 4. THE CALCULATION
                % This is the only number we need for the CSV summary.
                imagineWalkTime = GetSecs() - startTimeImagine; 
                
                if ~isempty(TL), TL.stopEvent(6, t, 'ImagineWalk'); end

                % ---------------------------------------------------------
                % THREE SECOND STATIONARY TIME PERIOD (IMAGINE STILL)
                % ---------------------------------------------------------
               
                % Trigger Channel 2 is used to mark this stationary epoch in the MEG.

                play_sound(pahandle, audioData.ImagineS);

                if ~isempty(TL), TL.startEvent(2, t, 'Stationary'); end
                
                WaitSecs(3.0); 
                
                if ~isempty(TL), TL.stopEvent(2, t, 'Stationary'); end

                % ---------------------------------------------------------
                % EVENT 5: OPEN EYES
                % ---------------------------------------------------------
                % [Trigger] Code 1: Instruction to open eyes
                if ~isempty(TL), TL.startEvent(7, t, 'OpenEyes'); end
                
                % [Audio] "Close your eyes" (Blocking: wait for sound to finish)
                play_sound_blocking(pahandle, audioData.OpenE);
                
                if ~isempty(TL), TL.stopEvent(7, t, 'OpenEyes'); end
                
                DrawFormattedText(win, 'Participant currently ranking...', 'center', 'center', [0 255 255]); % Cyan text to stand out
                Screen('Flip', win);
                
                play_sound(pahandle, audioData.Rank);
                rank = get_rank_key(); 
                
                % ---------------------------------------------------------
                % END OF TRIAL: RESEARCHER REDO CHECK
                % ---------------------------------------------------------
                % 1. Start with the raw simple math
                rawEncodeHead = actualHead - startHead;
                prodTurnAmount   = actHead - actualHead;

                rawEncodeTorso = actualTorso - startTorso;
                prodTorsoTurn   = actTorso - actualTorso;

                % 2. Fix the boundary crossing based on OptiTrack's layout
                if strcmp(dirCode, 'L')
                % OptiTrack: LEFT turns must be POSITIVE
                    if rawEncodeHead < 0, encodeTurnAmount = rawEncodeHead + 360; else, encodeTurnAmount = rawEncodeHead; end
    
                    if rawEncodeTorso < 0, encodeTorsoTurn = rawEncodeTorso + 360; else, encodeTorsoTurn = rawEncodeTorso; end

                elseif strcmp(dirCode, 'R')
                % OptiTrack: RIGHT turns must be NEGATIVE
                    if rawEncodeHead > 0, encodeTurnAmount = rawEncodeHead - 360; else, encodeTurnAmount = rawEncodeHead; end
    
                    if rawEncodeTorso > 0, encodeTorsoTurn = rawEncodeTorso - 360; else, encodeTorsoTurn = rawEncodeTorso; end
                end
                % ---------------------------------------------------------
                % END OF TRIAL: AUTO-SAVE DATA
                % ---------------------------------------------------------
                statusStr = 'Accepted'; % (Or 'Aborted_Mid_Trial' in the catch block)
                newRow = table(t, {participantPosition}, {dirCode}, {typeCode}, {qCode}, targetDeg, targetDist,...
                    walkDistTorso, walkDistHead, walkTime, startHead, startTorso, actualHead, actualTorso, turnTime, ...
                    encodeTurnAmount, encodeTorsoTurn, encodeDriftHead, encodeDriftTorso, actHead, actTorso, rt_Rot, prodTurnAmount, prodTorsoTurn, prodDriftHead, prodDriftTorso, imagineWalkTime, {rank}, attemptNum, {statusStr}, ...
                    'VariableNames', {'Trial', 'Position', 'Dir','Type','Q','TargetDeg', 'DistanceFromCent'...
                    'WalkDistTorso','WalkDistHead', 'WalkTime', 'StartHead', 'StartTorso', 'EncodeHead', 'EncodeTorso', 'EncodeTime', ...
                    'EncodeTurnAmountHead', 'EncodeTurnAmountTorso', 'EncodeDriftHead', 'EncodeDriftTorso', 'ProdHead', 'ProdTorso', 'RT_Rot', 'ProdTurnAmountHead', 'ProdTurnAmountTorso', 'ProdDriftHead', 'ProdDriftTorso', 'RT_ImagWalk', 'Rank', 'Attempt', 'Status'});
                
                results = [results; newRow];
                writetable(results, dataFile);
                
                % Save Traces here
                traceFilename = fullfile(traceFolder, sprintf('Trial_%02d_Attempt_%02d_Traces.mat', t, attemptNum));

                save(traceFilename, 'PhysicallyWalkHeadTrace', 'TorsoPhysicallyWalkHeadTrace', ...
                    'EncodingRotateHeadTrace', 'EncodingRotateTorsoTrace', ...
                    'ResponseRotationHeadTrace', 'ResponseRotationTorsoTrace', ...
                    'ImagineWalkingHeadTrace', 'ImagineWalkingTorsoTrace', ...
                    'PassiveEncodeHeadTrace', 'PassiveEncodeTorsoTrace', ...
                    'PassiveProdHeadTrace', 'PassiveProdTorsoTrace');
                
                play_sound_blocking(pahandle, audioData.Return); 
                trialAccepted = true; % Breaks the while loop, moves to next trial
                
            % ---------------------------------------------------------
                % NEW: BLOCK BREAK EVERY 8 TRIALS
                % ---------------------------------------------------------
                % If trial number is a multiple of 8, and it's not the very last trial
                if mod(t, 8) == 0 && t < size(trials, 1)
                    blockNum = t / 8;
                    
                    % Convert block number to a letter (1=A, 2=B, 3=C, etc.)
                    blockLetter = char(64 + blockNum);
                    
                    % Display break message using the letter
                    breakMsg = sprintf('End of Block %c.\n\nPlease take a moment to rest.\n\nResearcher: Press SPACE to begin the next block.', blockLetter);
                    DrawFormattedText(win, breakMsg, 'center', 'center', [0 255 0]); % Green text
                    Screen('Flip', win);
                    
                    % Wait for spacebar to resume
                    wait_key('space');
                    
                    % Clear screen to black before next trial starts
                    Screen('Flip', win);
                    WaitSecs(0.5); 
                end
                
            catch ME
                % --- THE MIDAIR ABORT SEQUENCE ---
                if strcmp(ME.message, 'Redo_Trial')
                    
                    PsychPortAudio('Stop', pahandle); 
                    if ~isempty(TL), TL.stopEvent(0, t, 'AbortClear'); end
                    
                    statusStr = 'Aborted_Mid_Trial';
                newRow = table(t, {participantPosition}, {dirCode}, {typeCode}, {qCode}, targetDeg, targetDist, ...
                    walkDistTorso, walkDistHead, walkTime, startHead, startTorso, actualHead, actualTorso, turnTime, ...
                    encodeTurnAmount, encodeTorsoTurn, encodeDriftHead, encodeDriftTorso, actHead, actTorso, rt_Rot, prodTurnAmount, prodTorsoTurn, prodDriftHead, prodDriftTorso, imagineWalkTime, {rank}, attemptNum, {statusStr}, ...
                    'VariableNames', {'Trial', 'Position', 'Dir','Type','Q','TargetDeg', 'DistanceFromCent'...
                    'WalkDistTorso','WalkDistHead', 'WalkTime', 'StartHead', 'StartTorso', 'EncodeHead', 'EncodeTorso', 'EncodeTime', ...
                    'EncodeTurnAmountHead', 'EncodeTurnAmountTorso', 'EncodeDriftHead', 'EncodeDriftTorso', 'ProdHead', 'ProdTorso', 'RT_Rot', 'ProdTurnAmountHead', 'ProdTurnAmountTorso', 'ProdDriftHead', 'ProdDriftTorso', 'RT_ImagWalk', 'Rank', 'Attempt', 'Status'});
                    
                    results = [results; newRow];
                    writetable(results, dataFile);
                    
                    traceFilename = fullfile(traceFolder, sprintf('Trial_%02d_Attempt_%02d_Traces.mat', t, attemptNum));
                save(traceFilename, 'PhysicallyWalkHeadTrace', 'TorsoPhysicallyWalkHeadTrace', ...
                    'EncodingRotateHeadTrace', 'EncodingRotateTorsoTrace', ...
                    'ResponseRotationHeadTrace', 'ResponseRotationTorsoTrace', ...
                    'ImagineWalkingHeadTrace', 'ImagineWalkingTorsoTrace', ...
                    'PassiveEncodeHeadTrace', 'PassiveEncodeTorsoTrace', ...
                    'PassiveProdHeadTrace', 'PassiveProdTorsoTrace');
                    
                    attemptNum = attemptNum + 1;
                   
                    
                    DrawFormattedText(win, 'TRIAL ABORTED.\n\nPlease return to the start.', 'center', 'center', [255 0 0]);
                    Screen('Flip', win);
                    play_sound_blocking(pahandle, audioData.Return);
                    WaitSecs(2.0); 
                    
                    continue; 
                    
                else
                    rethrow(ME); % Normal MATLAB error handling
                end
            end % <-- END OF TRY-CATCH
            
        end % --- END OF WHILE LOOP ---
    end % --- END OF 64 TRIALS ---
% ---------------------------------------------------------
% STEP 2: CRASH RECOVERY (The Catch Block)
% ---------------------------------------------------------
% This block only runs if something breaks or you hit ESCAPE.
catch ME
    % Ensures hardware is cleanly disconnected to prevent computer crashes
    if ~isempty(TL), TL.close(); end
    OptiTrackBridge.Disconnect();
    PsychPortAudio('Close');
    Screen('CloseAll');
    
    if strcmp(ME.message, 'User Quit')
        fprintf('\n--- Aborted by researcher (ESCAPE). Results saved to: %s ---\n', dataFile);
    else
        rethrow(ME); % Show the actual error if it wasn't a manual quit
    end

    compileData(traceFolder);

    return;

end


% ---------------------------------------------------------
% STEP 3: NORMAL CLEANUP
% ---------------------------------------------------------
% Standard: This runs when the experiment finishes successfully.
if ~isempty(TL), TL.close(); end
OptiTrackBridge.Disconnect();
PsychPortAudio('Close');
Screen('CloseAll');
disp('Experiment finished successfully. Data saved.');

compileData(traceFolder);


end

% ---------------------------------------------------------
% HELPER FUNCTIONS
% ---------------------------------------------------------
    function play_sound(pa, wav)
        % Plays audio and immediately moves to the next line of code
        PsychPortAudio('FillBuffer', pa, wav);
        PsychPortAudio('Start', pa, 1, 0, 1);
    end

    function play_sound_blocking(pa, wav)
        % Plays audio and pauses MATLAB until the audio finishes playing
        PsychPortAudio('FillBuffer', pa, wav);
        PsychPortAudio('Start', pa, 1, 1, 1); 
        PsychPortAudio('Stop', pa, 1);        
    end

    function wait_key(name)
        % Standard: Pauses experiment until specific key is pressed
        KbReleaseWait;
        while true
            [kd, ~, kc] = KbCheck;
            if kd && kc(KbName(name)), break; end
            if kd && kc(KbName('ESCAPE')), error('User Quit'); end
        end
    end

    function k = get_rank_key()
    % Captures 6, 7, 8, or 9 ONLY. Ignores all other keys.
    KbReleaseWait;  
    k = ''; 
    
    % Define the specific keys we care about
    validKeys = [KbName('6^'), KbName('7&'), KbName('8*'), KbName('9(')];
    escKey = KbName('ESCAPE');

    while isempty(k)
        [kd, ~, kc] = KbCheck;
        if kd
            % Check for ESCAPE first (Safety Exit)
            if kc(escKey), error('User Quit'); end
            
            % Check if the pressed key is in our valid list
            if any(kc(validKeys))
                % Find which one was pressed and map it to a Rank (0-3)
                if kc(KbName('6^')), k = '0'; end
                if kc(KbName('7&')), k = '1'; end
                if kc(KbName('8*')), k = '2'; end
                if kc(KbName('9(')), k = '3'; end
            else
             
            end
        end
    end
    end
    function compileData(targetFolder)
        disp('Compiling Master Table from Trace files...');
        
        traceLabels = {'PhysicallyWalkHeadTrace', 'TorsoPhysicallyWalkHeadTrace', ...
                       'EncodingRotateHeadTrace', 'EncodingRotateTorsoTrace', ...
                       'ResponseRotationHeadTrace', 'ResponseRotationTorsoTrace', ...
                       'ImagineWalkingHeadTrace', 'ImagineWalkingTorsoTrace'};

% Find all .mat files in the target folder that match the specific naming convention
matFiles = dir(fullfile(targetFolder, 'Trial_*_Attempt_*_Traces.mat'));

% Safety check: Abort script if no files matching the pattern are found
if isempty(matFiles), error('No files found.'); end
 
% Initialize empty arrays to store the extracted trial and attempt numbers
trialList = []; 
attemptList = [];

% Loop through every discovered file to extract metadata from the filenames
for i = 1:length(matFiles)
    % Use regular expressions to pull the numbers following 'Trial_' and 'Attempt_'
    tokens = regexp(matFiles(i).name, 'Trial_(\d+)_Attempt_(\d+)', 'tokens');
    
    % Convert the extracted string tokens into double-precision numbers and store them
    trialList(i)   = str2double(tokens{1}{1}); % The Trial ID (e.g., Trial_12 -> 12)
    attemptList(i) = str2double(tokens{1}{2}); % The Attempt ID (e.g., Attempt_3 -> 3)
end
 
% =========================================================================
% 2. Pre-Scan for Maximums
% =========================================================================
% We need the absolute maximum time-series length to preallocate the 3rd dimension of our 5D block
maxTimeLen = 0; 

% Iterate through all found files to inspect their contents
for i = 1:length(matFiles)
    % Load the data structure from the current .mat file
    trialData = load(fullfile(matFiles(i).folder, matFiles(i).name));
    
    % Check each of our target traces to see if they exist in this specific file
    for trIdx = 1:length(traceLabels)
        if isfield(trialData, traceLabels{trIdx})
            % Extract the trace structure (e.g., walkTraces)
            S = trialData.(traceLabels{trIdx});
            
            % Ensure it is actually a structure before trying to read its fields
            if isstruct(S)
                fNames = fieldnames(S); % Get all field names (e.g., 'x', 'y', 'time')
                
                % Check the length of the data inside each field
                for f = 1:length(fNames)
                    % Update maxTimeLen if this field's length is greater than the current max
                    maxTimeLen = max(maxTimeLen, length(S.(fNames{f})));
                end
            end
        end
    end
end
 
% =========================================================================
% 3. Preallocate the 5D Array [Trial x Attempt x Time x Trace x Channel]
% =========================================================================
% Dimension 1: Trial ID (Ensures the matrix has at least 64 rows, or more if trial IDs go higher)
numTrials   = max(64, max(trialList)); 

% Dimension 2: Attempt ID (The maximum attempt number across all trials)
numAttempts = max(attemptList);        

% Dimension 3: Time/Samples (Pre-scanned above) -> maxTimeLen

% Dimension 4: Trace Type (The number of distinct variables we are looking for)
numTraces   = length(traceLabels);     

% Dimension 5: Data Channels (7 specific channels defined below)
numChannels = 7;                       % 1:Time, 2:X, 3:Y, 4:Z, 5:Roll, 6:Pitch, 7:Yaw
 
% Create the massive 5D block, prefilled with NaNs (Not-a-Number) to handle missing data gracefully
Master5D = NaN(numTrials, numAttempts, maxTimeLen, numTraces, numChannels);
 
% =========================================================================
% 4. Fill the 5D Array
% =========================================================================
% Get a list of unique trials so we can process them one by one
uniqueTrials = unique(trialList);
 
for tIdx = 1:length(uniqueTrials)
    tID = uniqueTrials(tIdx); % The actual numeric ID of the current trial
    
    % Find all attempt numbers associated with this specific trial, sorted lowest to highest
    attemptsForTrial = sort(attemptList(trialList == tID));
    
    % Loop through every attempt for this trial
    for aIdx = 1:length(attemptsForTrial)
        currAttempt = attemptsForTrial(aIdx); % The actual numeric ID of the current attempt
        
        % Locate the specific file index that matches both the current Trial ID and Attempt ID
        fIdx = find(trialList == tID & attemptList == currAttempt, 1);
        
        % Load that specific file into memory
        trialData = load(fullfile(matFiles(fIdx).folder, matFiles(fIdx).name));
 
        % Loop through all the possible trace names we defined at the top
        for trIdx = 1:numTraces
            varName = traceLabels{trIdx}; % e.g., 'walkTraces'
            
            % Check if this specific trace exists in the currently loaded file
            if isfield(trialData, varName)
                S = trialData.(varName); % Extract the trace data
                
                % Proceed only if the trace is structured appropriately
                if isstruct(S)
                    fNames = fieldnames(S); % Get the internal channel names (x, y, time, etc.)
                    
                    % Loop through each internal channel
                    for f = 1:length(fNames)
                        fname = lower(fNames{f}); % Convert to lowercase to make matching case-insensitive
                        dataVal = S.(fNames{f});  % Extract the actual numeric array
                        dataVal = dataVal(:);     % Force the array into a column vector (N x 1)
                        currLen = length(dataVal); % Number of time samples in this specific array
                        
                        % Map the string field name to our 5th Dimension (Channel Index 1 through 7)
                        chanIdx = 0; % Default to 0 (unmapped)
                        switch fname
                            case 'time',  chanIdx = 1; % Channel 1 is Time
                            case 'x',     chanIdx = 2; % Channel 2 is X-coordinate
                            case 'y',     chanIdx = 3; % Channel 3 is Y-coordinate
                            case 'z',     chanIdx = 4; % Channel 4 is Z-coordinate
                            case 'roll',  chanIdx = 5; % Channel 5 is Roll orientation
                            case 'pitch', chanIdx = 6; % Channel 6 is Pitch orientation
                            case 'yaw',   chanIdx = 7; % Channel 7 is Yaw orientation
                        end
                        
                        % If the field name matched one of our predefined channels, insert the data
                        if chanIdx > 0
                            % Insert into the massive matrix at the correct coordinates:
                            % (Trial ID, Attempt ID, Time 1 to N, Trace Index, Channel Index)
                            Master5D(tID, currAttempt, 1:currLen, trIdx, chanIdx) = dataVal;
                        end
                    end
                end
            end
        end
    end
end
end
 
% Print a success message showing the final size of the generated array
fprintf('5D Array successfully built. Dimensions: %d x %d x %d x %d x %d\n', size(Master5D));

outputFileName = 'Testing_Master_Data.mat';

% Save the Master5D variable and metadata for reference
% Using '-v7.3' because 5D arrays can easily exceed the 2GB limit for standard .mat files
fprintf('Saving data to %s... ', outputFileName);
save(outputFileName, 'Master5D', 'traceLabels', '-v7.3');
fprintf('Done.\n');

fprintf('5D Array successfully built and saved. Dimensions: %d x %d x %d x %d x %d\n', size(Master5D));
