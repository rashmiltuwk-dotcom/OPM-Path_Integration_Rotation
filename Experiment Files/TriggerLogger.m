classdef TriggerLogger < handle
    % TRIGGERLOGGER: The Hardware Bridge for MEG Syncing
    % Manages Channels 1-7 for MEG TTL (Transistor-Transistor Logic) pulses.
    % It simultaneously fires a "Master Sync" pulse on Channel 8 (Pin 9 / Value 128)
    % for every event. It also maintains a CSV Log File as a failsafe backup.
    
    properties
        % [HARDWARE SETUP]
        ioObj           % The io64 driver object that allows MATLAB to talk directly to the CPU/Motherboard
        address         % The physical hex address of the parallel port (usually '378' / Decimal 888)
        
        % [DATA BACKUP SETUP]
        logFileID       % The open ID handle for the CSV text file
        expStartTime    % The absolute baseline time (T=0) to calculate precise relative timestamps
    end
    
    methods
        function obj = TriggerLogger(portAddress, subjectID)
            % ---------------------------------------------------------
            % CONSTRUCTOR: Runs once when the main script calls TL = TriggerLogger(...)
            % ---------------------------------------------------------
            
            % --- 1. Initialize the physical MEG port ---
            obj.ioObj = io64;           % Wake up the custom io64 driver
            status = io64(obj.ioObj);   % Check if the driver successfully loaded
            obj.address = portAddress;  % Store the port address
            
            % [SAFETY RESET] Immediately blast 0 Volts to all pins. 
            % This clears any "ghost" 5V signals left over from a previous crashed run,
            % ensuring the MEG machine has a clean slate to detect new triggers.
            io64(obj.ioObj, obj.address, 0); 
            
            % --- 2. Initialize The Failsafe Log File ---
            % Create a unique filename using the Participant ID and exact current time
            logName = sprintf('Log_Subj%s_%s.csv', subjectID, datestr(now, 'yyyymmdd_HHMM'));
            
            % Open the file in 'a' (append) mode so we can continuously write to it
            obj.logFileID = fopen(logName, 'a');
            
            % Write the top header row for the CSV columns
            fprintf(obj.logFileID, 'SystemTime,TrialNum,EventName,TriggerChannel,PortValueSent,State\n');
            
            % --- 3. Start the Master Clock ---
            % Grab the exact computer time right now. All future events will be 
            % measured relative to this exact millisecond.
            obj.expStartTime = GetSecs; 
            
            disp(['TriggerLogger Initialized. Hardware Sync on Ch 8. Log saving to: ' logName]);
        end
        
        function startEvent(obj, triggerChannel, trialNum, eventName)
            % ---------------------------------------------------------
            % START EVENT: Sends 5V to the MEG and writes "ON" to the CSV
            % ---------------------------------------------------------
            
            
            
            % --- 1. The Binary Conversion Math ---
            % Parallel ports use an 8-bit binary system. You can't just send the number '3' 
            % to trigger Channel 3. You must convert the channel number into its binary place value.
            % Formula: 2^(Channel - 1). 
            % Examples: Ch 1 = 1, Ch 2 = 2, Ch 3 = 4, Ch 4 = 8, Ch 5 = 16, etc.
            bitValue = 2^(triggerChannel - 1); 
            
            % --- 2. The Master Sync Trick (Bitwise OR) ---
            
            
            % Channel 8 represents the 8th binary bit, which has a decimal value of 128.
            % 'bitor' mathematically forces the 8th bit to ALWAYS be on (1), 
            % alongside whatever target channel you requested. 
            % Example: If you want Ch 3 (Value 4), bitor(4, 128) sends 132 to the port.
            outValue = bitor(bitValue, 128); 
            
            % --- 3. Send physical TTL HIGH ---
            % Push the calculated number to the port. The hardware translates this into 
            % 5 Volts of physical electricity sent down the corresponding cables.
            io64(obj.ioObj, obj.address, outValue); 
            
            % --- 4. Write to CSV Log ---
            % Calculate how many seconds have passed since the experiment started
            timestamp = GetSecs - obj.expStartTime;
            
            % Write the data row. '%.4f' means print the time with 4 decimal places (sub-millisecond precision).
            fprintf(obj.logFileID, '%.4f,%d,%s,%d,%d,ON\n', ...
                timestamp, trialNum, eventName, triggerChannel, outValue);
        end
        
        function stopEvent(obj, triggerChannel, trialNum, eventName)
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
                timestamp, trialNum, eventName, triggerChannel);
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
