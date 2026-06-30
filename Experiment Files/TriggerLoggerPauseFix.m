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
        
            % Channels 2-7 = binary 01111110 = decimal 126
            allChannels = 126;
            eventName = 'ExperimentStart';
            
            % Fire channels 2-7 HIGH
            io64(obj.ioObj, obj.address, allChannels);
            
            
            % Brief hold so hardware registers the pulse
            WaitSecs(0.05);
            
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

        function pauseIndicatorStart(obj, triggerChannel, trueTrial, eventName)
            % ---------------------------------------------------------
            % PAUSE START: Pauses the active trigger channel and logs the pause event
            % 
            % LOGIC:
            % 1. Read the current port state (e.g., 132 for Ch3 + Master Sync)
            % 2. Drop ALL triggers to 0V (silent period during pause)
            % 3. Log which channel was paused (activeChannel) for CSV readability
            %
            % The key insight: prePauseValue stores the EXACT number that was
            % sent to the port before pause (e.g., 132). This encodes both the
            % active channel AND the Master Sync bit. When resumed, sending this
            % exact number back restores everything perfectly.
            % ---------------------------------------------------------
            
            % --- 1. SNAPSHOT: Save the exact port state before dropping it ---
            % This reads back the current value on the port (e.g., 132 if Ch3 is active)
            % The value encodes: activeChannel (bits 1-7) + Master Sync (bit 8)
            obj.prePauseValue = io64(obj.ioObj, obj.address);
        
            % --- 2. DROP ALL TRIGGERS TO 0V ---
            % This immediately silences the port. The active channel goes DOWN (0V)
            % along with the Master Sync. The MEG will record this as a falling edge.
            io64(obj.ioObj, obj.address, 0);
            
            % --- 3. LOG THE PAUSE EVENT ---
            % Log WHEN the pause happened, WHICH channel was running (activeChannel),
            % and that the port is now at 0 (silent).
            % The CSV row will look like: "7.5000,1,PauseIndicator,3,0,OFF"
            % Meaning: At 7.5s, trial 1, Channel 3 was paused and dropped to 0
            timestamp = GetSecs - obj.expStartTime;
            fprintf(obj.logFileID, '%.4f,%d,%s,%d,0,OFF\n', ...
                timestamp, trueTrial, 'PauseIndicator', obj.activeChannel);
        end

        function pauseIndicatorEnd(obj, triggerChannel, trueTrial, eventName)
            % ---------------------------------------------------------
            % PAUSE END: Resumes the trigger channel that was active before the pause
            %
            % LOGIC:
            % 1. Restore the port to its pre-pause state (prePauseValue)
            % 2. This automatically brings back the active channel to 5V
            % 3. Log the resumption with the restored port value
            %
            % Why does this work? Because prePauseValue contains the complete
            % port state from before the pause (e.g., 132 for Ch3 + Master Sync).
            % Sending 132 back to the port activates Ch3 and the Master Sync exactly
            % as they were before, creating a rising edge in the MEG.
            % ---------------------------------------------------------

            % --- 1. RESTORE pre-pause port state ---
            % Send the EXACT number that was on the port before pause back to the port.
            % If it was 132 (Ch3 + Master Sync) before, it becomes 132 again now.
            % This triggers a rising edge in the MEG and brings Ch3 back to 5V.
            io64(obj.ioObj, obj.address, obj.prePauseValue);
        
            % --- 2. LOG THE RESUME EVENT ---
            % Log WHEN the resume happened, WHICH channel is running again (activeChannel),
            % and what value was restored to the port (prePauseValue).
            % The CSV row will look like: "10.0000,1,PauseIndicator,3,132,ON"
            % Meaning: At 10.0s, trial 1, Channel 3 resumed at port value 132 (5V)
            timestamp = GetSecs - obj.expStartTime;
            fprintf(obj.logFileID, '%.4f,%d,%s,%d,%d,ON\n', ...
                timestamp, trueTrial, 'PauseIndicator', obj.activeChannel, obj.prePauseValue);
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
