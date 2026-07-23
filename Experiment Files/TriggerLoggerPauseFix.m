classdef TriggerLogger < handle
    % TRIGGERLOGGER: The Hardware Bridge for MEG Syncing
    % Manages Channels 1-7 for MEG TTL (Transistor-Transistor Logic) pulses.
    % Simultaneously fires a "Master Sync" pulse on Channel 8 (Value 128)
    % for every event. Maintains a CSV Log File as a failsafe backup.

    
    properties
        % [HARDWARE SETUP]
        ioObj           % The io64 driver object that allows MATLAB to talk directly to the CPU/Motherboard
        address         % The physical hex address of the parallel port (usually '378' / Decimal 888)
        
        % [DATA BACKUP SETUP]
        logFileID       % The open ID handle for the CSV text file
        expStartTime    % The absolute baseline time (T=0) to calculate precise relative timestamps
        prePauseValue   % Stores the exact port state (e.g., 132) BEFORE pause is called
                        % This is the full number sent to the port, encoding the active channel + Master Sync
                        % Used to restore everything exactly as it was when resume is called
        
        activeChannel = 0; % Stores which channel (1-7) is currently active (running at 5V)
                           % CRITICAL FOR PAUSE SYSTEM: When pause is triggered, this tells us
                           % which channel was running so we can restore it when resumed.
                           % Also logged to CSV for human readability (e.g., "Channel 3 paused")
    end
    
    methods
        function obj = TriggerLogger(subjectID)
            obj.address = hex2dec('3FF8');  % Correct address from your test script
            
            obj.ioObj = io64;
            status = io64(obj.ioObj);
            if status ~= 0
                error('TriggerLogger:NoHardware', 'Failed to initialize io64.');
            end
            io64(obj.ioObj, obj.address, 0);  % safety reset
            
            logName = sprintf('Log_Subj%s_%s.csv', subjectID, datestr(now, 'yyyymmdd_HHMM'));
            obj.logFileID = fopen(logName, 'a');
            fprintf(obj.logFileID, 'SystemTime,trueTrial,EventName,TriggerChannel,PortValueSent,State\n');
            obj.expStartTime = GetSecs;
            
            disp(['TriggerLogger Initialized. Log saving to: ' logName]);
        end
        
        function callExperimentStart(obj, trueTrial)
            OptiTrackBridge.MarkTimeZero();
            io64(obj.ioObj, obj.address, 255);
            timestamp = GetSecs - obj.expStartTime;
            fprintf(obj.logFileID, '%.4f,%d,%s,ALL,255,ON\n', timestamp, trueTrial, 'ExperimentStart');
        
            WaitSecs(0.05);
        
            io64(obj.ioObj, obj.address, 0);
            fprintf(obj.logFileID, '%.4f,%d,%s,ALL,0,OFF\n', GetSecs - obj.expStartTime, trueTrial, 'ExperimentStart');
        end

        function startEvent(obj, triggerChannel, trueTrial, eventName)
            % ---------------------------------------------------------
            % START EVENT: Sends 5V to the MEG and writes "ON" to the CSV
            % Also stores the active channel for pause/resume logic
            % ---------------------------------------------------------
            
            % --- 1. The Binary Conversion Math ---
            % Parallel ports use an 8-bit binary system. You can't just send the number '3' 
            % to trigger Channel 3. You must convert the channel number into its binary place value.
            % Formula: 2^(Channel - 1). 
            % Examples: Ch 1 = 1, Ch 2 = 2, Ch 3 = 4, Ch 4 = 8, Ch 5 = 16, Ch 6 = 32, Ch 7 = 64
            bitValue = 2^(triggerChannel - 1); 
            
            % --- 2. The Master Sync Pulse ---
            % Channel 8 (Value 128) fires on every event to create a sync pulse in the MEG.
            % 'bitor' mathematically forces the 8th bit to ALWAYS be on (1), 
            % alongside whatever target channel you requested. 
            % Example: If you want Ch 3 (Value 4), bitor(4, 128) sends 132 to the port.
            outValue = bitor(bitValue, 128); 
            
            % --- 3. Send physical TTL HIGH ---
            % Push the calculated number to the port. The hardware translates this into 
            % 5 Volts of physical electricity sent down the corresponding cables.
            io64(obj.ioObj, obj.address, outValue);

            % --- 4. TRACK THE ACTIVE CHANNEL ---
            % Store which channel (1-7) is currently active. This is CRITICAL for the pause system:
            % When the participant pauses, we need to remember which channel was running
            % so we can restore it when they resume. Without this, we wouldn't know which
            % channel to bring back up after the pause ends.
            % Example: If startEvent(3, ...) is called, activeChannel becomes 3
            obj.activeChannel = triggerChannel;
            
            % --- 5. Write to CSV Log ---
            % Calculate how many seconds have passed since the experiment started
            timestamp = GetSecs - obj.expStartTime;
            
            % Write the data row. '%.4f' means print the time with 4 decimal places (sub-millisecond precision).
            fprintf(obj.logFileID, '%.4f,%d,%s,%d,%d,ON\n', ...
                timestamp, trueTrial, eventName, triggerChannel, outValue);
        end
        
        function stopEvent(obj, triggerChannel, trueTrial, eventName)
            % ---------------------------------------------------------
            % STOP EVENT: Drops the MEG pins to 0V and writes "OFF" to the CSV
            % ---------------------------------------------------------
            
            % --- 1. Send physical TTL LOW ---
            % MEG triggers require a "Rising Edge" (a jump from 0V to 5V) to register a mark.
            % Therefore, we MUST turn the pins back off (send 0) before we can fire them again.
            io64(obj.ioObj, obj.address, 0); 
            
            % --- 2. Write to CSV Log ---
            % Note exactly when the pulse ended in our backup file.
            timestamp = GetSecs - obj.expStartTime;
            fprintf(obj.logFileID, '%.4f,%d,%s,%d,0,OFF\n', ...
                timestamp, trueTrial, eventName, triggerChannel);
        end

        function resetAllTriggers(obj, trueTrial)
            % ---------------------------------------------------------
            % RESET ALL TRIGGERS: Fires all channels 1-7 together, then drops to 0
            % Creates a clear "abort marker" pulse visible in the MEG data
            % ---------------------------------------------------------
        
            % All channels 1-7 = binary 01111111 = decimal 127
            allChannels = 127;
        
            % Add Master Sync (Channel 8)
            outValue = bitor(allChannels, 128);  % = 255 (binary 11111111)
        
            % Fire all channels HIGH
            io64(obj.ioObj, obj.address, outValue);
        
            % Log it
            timestamp = GetSecs - obj.expStartTime;
            fprintf(obj.logFileID, '%.4f,%d,%s,ALL,255,ON\n', ...
                timestamp, trueTrial, 'AbortReset');
        
            % Brief hold so hardware registers the pulse
            WaitSecs(0.05);
        
            % Drop all channels to LOW
            io64(obj.ioObj, obj.address, 0);
            fprintf(obj.logFileID, '%.4f,%d,%s,ALL,0,OFF\n', ...
                GetSecs - obj.expStartTime, trueTrial, 'AbortReset');
        end

        % ---------------------------------------------------------
        % PAUSE START: Fires a pulse to mark the beginning of a pause.
        % Saves the current port state first so it can be restored on resume,
        % preventing any active event channel from being wiped when the
        % pause fires mid-trial.
        %
        % The function is queued by a keyboard input (P for PAUSE) in the main
        % code (not done here).
        % ---------------------------------------------------------
        function pauseIndicatorStart(obj, triggerChannel, trueTrial, eventName)
            % --- 1. Save current port state ---
            % Read back whatever is currently active on the port so we can
            % restore it when the experiment resumes.
            obj.prePauseValue = io64(obj.ioObj, obj.address);

                % --- 2. KEEPING OTHER FUNCTION ALIVE + ADD PAUSE MARKER ---
            % Instead of replacing, combine: 
            % prePauseValue keeps Ch3 + Ch8, we ADD Ch1 + Ch7 on top
            pauseMarker = 65;  % Ch1 + Ch7
            outValue = bitor(obj.prePauseValue, pauseMarker);
            io64(obj.ioObj, obj.address, outValue);

            % --- 3. Write to CSV Log ---
            timestamp = GetSecs - obj.expStartTime;
            fprintf(obj.logFileID, '%.4f,%d,%s,%d,%d,ON\n', ...
                timestamp, trueTrial, 'PauseIndicator', 65, outValue);
        end


        function pauseIndicatorEnd(obj, triggerChannel, trueTrial, eventName)
            % ---------------------------------------------------------
            % PAUSE END: Restores the port to its pre-pause state and logs resumption.
            % Sending prePauseValue (rather than 0) ensures any event channel
            % that was active when the pause was triggered is correctly restored.
            % ---------------------------------------------------------

            % --- 1. Restore pre-pause port state ---
            io64(obj.ioObj, obj.address, obj.prePauseValue);

            % --- 2. Write to CSV Log ---
            timestamp = GetSecs - obj.expStartTime;
            fprintf(obj.logFileID, '%.4f,%d,%s,%d,%d,OFF\n', ...
                timestamp, trueTrial, 'PauseIndicator', 65, obj.prePauseValue);
        end

        function close(obj)
            % ---------------------------------------------------------
            % CLEANUP: Runs safely at the end of the experiment or during a crash
            % ---------------------------------------------------------
            
            % Send one final 0 to the port to ensure the hardware is resting safely at 0 Volts
            io64(obj.ioObj, obj.address, 0);
            
            % Safely close the CSV file so it saves properly to the hard drive and isn't corrupted
            fclose(obj.logFileID);
            
            disp('Experiment complete. Trigger hardware reset and Log closed.');
        end
    end
end
