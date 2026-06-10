classdef OptiTrackBridge
    % OPTITRACKBRIDGE (Polling-based, Stripped)
    % Minimal interface: Connect, Disconnect, Event Logging, Continuous Collection, Recording
    
    properties (Constant)
        FORCE_DUMMY_MODE = false;

        % --- NETWORKING ---
        HOST_IP   = '128.40.164.130';
        CLIENT_IP = '128.40.164.174';

        % --- RIGID BODY IDs ---
        HEAD_ID  = 1;
        TORSO_ID = 2;
    end

    methods (Static)

        % =================================================================
        % CONNECT / DISCONNECT
        % =================================================================
        function success = Connect(subjectID)
            global OP_BRIDGE_STATE OP_EVENT_LOG

            clear global OP_BRIDGE_STATE OP_EVENT_LOG;
            global OP_BRIDGE_STATE OP_EVENT_LOG

            % Initialize state struct
            OP_BRIDGE_STATE.NatNetClient = [];
            OP_BRIDGE_STATE.IsConnected = false;
            OP_BRIDGE_STATE.IsDummy = false;
            
            % Initialize continuous data collection
            OP_BRIDGE_STATE.ContinuousActive = false;
            OP_BRIDGE_STATE.ContinuousData = [];
            OP_BRIDGE_STATE.ContinuousStartTime = 0;
            
            % Initialize event log
            OP_EVENT_LOG.time  = [];
            OP_EVENT_LOG.trial = [];
            OP_EVENT_LOG.event = {};
            OP_EVENT_LOG.state = {};

            if OptiTrackBridge.FORCE_DUMMY_MODE
                OP_BRIDGE_STATE.IsDummy = true;
                success = true;
                return;
            end

            try
                fprintf('Creating natnet class object...\n');
                OP_BRIDGE_STATE.NatNetClient = natnet;

                fprintf('Connecting to the server at %s...\n', OptiTrackBridge.HOST_IP);
                OP_BRIDGE_STATE.NatNetClient.HostIP = OptiTrackBridge.HOST_IP;
                OP_BRIDGE_STATE.NatNetClient.ClientIP = OptiTrackBridge.CLIENT_IP;
                OP_BRIDGE_STATE.NatNetClient.ConnectionType = 'Multicast';

                OP_BRIDGE_STATE.NatNetClient.connect;

                if (OP_BRIDGE_STATE.NatNetClient.IsConnected == 0)
                    warning('Client failed to connect. Check IPs and Motive streaming settings.');
                    OP_BRIDGE_STATE.IsDummy = true;
                    success = false;
                else
                    OP_BRIDGE_STATE.IsConnected = true;
                    success = true;
                    fprintf('Connected to Motive successfully.\n');
                end
                
            catch ME
                warning('Connection Failed: %s', ME.message);
                OP_BRIDGE_STATE.IsDummy = true;
                success = false;
            end
        end
        
        function Disconnect()
            global OP_BRIDGE_STATE OP_EVENT_LOG
            if ~isempty(OP_BRIDGE_STATE) && ~OP_BRIDGE_STATE.IsDummy
                try 
                    OP_BRIDGE_STATE.NatNetClient.disconnect;
                catch
                end
            end
            clear global OP_BRIDGE_STATE OP_EVENT_LOG;
        end

        % =================================================================
        % EVENT LOGGING
        % =================================================================
        function startEvent(trialNum, eventName)
            global OP_EVENT_LOG
            i = length(OP_EVENT_LOG.time) + 1;
            OP_EVENT_LOG.time(i)  = GetSecs();
            OP_EVENT_LOG.trial(i) = trialNum;
            OP_EVENT_LOG.event{i} = eventName;
            OP_EVENT_LOG.state{i} = 'START';
        end

        function stopEvent(trialNum, eventName)
            global OP_EVENT_LOG
            i = length(OP_EVENT_LOG.time) + 1;
            OP_EVENT_LOG.time(i)  = GetSecs();
            OP_EVENT_LOG.trial(i) = trialNum;
            OP_EVENT_LOG.event{i} = eventName;
            OP_EVENT_LOG.state{i} = 'STOP';
        end

        % =================================================================
        % CONTINUOUS DATA COLLECTION
        % =================================================================
        function StartContinuousCollection()
            global OP_BRIDGE_STATE
            OP_BRIDGE_STATE.ContinuousActive = true;
            OP_BRIDGE_STATE.ContinuousData = [];
            OP_BRIDGE_STATE.ContinuousStartTime = GetSecs();
            fprintf('>>> Continuous data collection STARTED\n');
        end

        function StopContinuousCollection()
            global OP_BRIDGE_STATE
            OP_BRIDGE_STATE.ContinuousActive = false;
            fprintf('>>> Continuous data collection STOPPED (%d frames)\n', length(OP_BRIDGE_STATE.ContinuousData));
        end

        function CollectFrameToContinuous()
            global OP_BRIDGE_STATE
            
            if ~OP_BRIDGE_STATE.ContinuousActive || OP_BRIDGE_STATE.IsDummy
                return;
            end

            try
                data = OP_BRIDGE_STATE.NatNetClient.getFrame();
                if isempty(data), data = OP_BRIDGE_STATE.NatNetClient.GetLastFrameOfData(); end
                if isempty(data) || isempty(data.RigidBody), return; end
                
                % Timestamp relative to collection start
                relTime = GetSecs() - OP_BRIDGE_STATE.ContinuousStartTime;
                
                % Loop through all rigid bodies in this frame
                for i = 1:data.RigidBody.Length
                    rb = data.RigidBody(i);
                    
                    frame = struct();
                    frame.timestamp = relTime;
                    
                    % Safe extraction of the Motive timestamp to prevent .NET crashes
                    try
                        frame.motive_timestamp = double(data.Timestamp);
                    catch
                        frame.motive_timestamp = NaN;
                    end
                    
                    frame.rbID = rb.ID;
                    frame.x = double(rb.x);
                    frame.y = double(rb.y);
                    frame.z = double(rb.z);
                    frame.qw = double(rb.qw);
                    frame.qx = double(rb.qx);
                    frame.qy = double(rb.qy);
                    frame.qz = double(rb.qz);
                    
                    % Compute Euler angles
                    [roll, pitch, yaw] = OptiTrackBridge.QuatToEuler(frame.qw, frame.qx, frame.qy, frame.qz);
                    frame.roll = roll;
                    frame.pitch = pitch;
                    frame.yaw = yaw;
                    
                    % Append to continuous storage
                    if isempty(OP_BRIDGE_STATE.ContinuousData)
                        OP_BRIDGE_STATE.ContinuousData = frame;
                    else
                        OP_BRIDGE_STATE.ContinuousData(end+1) = frame;
                    end
                end
                
            catch ME
                % Fail silently as per polling structure, to not interrupt loop
            end
        end

        function SaveContinuous(filename)
            global OP_BRIDGE_STATE
            
            if isempty(OP_BRIDGE_STATE.ContinuousData)
                fprintf('>>> No continuous data to save\n');
                return;
            end
            
            continuousData = OP_BRIDGE_STATE.ContinuousData;
            
            try
                save(filename, 'continuousData', '-v7.3');
                fprintf('>>> Continuous data saved to: %s (%d frames)\n', filename, length(continuousData));
            catch ME
                fprintf('>>> Error saving continuous data: %s\n', ME.message);
            end
        end

        % =================================================================
        % RECORD UNTIL KEY
        % =================================================================
        function [finalHead, finalTorso, headTrace, torsoTrace] = RecordUntilKey(headID, torsoID, keyName, win)
            global OP_BRIDGE_STATE
            
            targetKey = KbName(keyName);
            escKey = KbName('ESCAPE');
            xKey = KbName('x'); rKey = KbName('r');

            if OP_BRIDGE_STATE.IsDummy
                DrawFormattedText(win, sprintf('DUMMY MODE: Press "x" (or %s) to finish.', keyName), 'center', 'center', [255 255 0]);
                Screen('Flip', win);
                while true
                    [kd, ~, kc] = KbCheck;
                    if kd && any(kc(escKey)), error('User Quit'); end
                    if kd && any(kc(rKey)), error('Redo_Trial'); end
                    if kd && (any(kc(targetKey)) || any(kc(xKey))), WaitSecs(0.3); break; end
                end
                finalHead = 0; finalTorso = 0;
                headTrace = OptiTrackBridge.EmptyTrace(); torsoTrace = OptiTrackBridge.EmptyTrace();
                return; 
            end

            startTime = GetSecs();
            white = WhiteIndex(win);
            
            maxSamples = 10000;
            tData = nan(maxSamples, 1);
            hxData = nan(maxSamples, 1); hyData = nan(maxSamples, 1); hzData = nan(maxSamples, 1);
            hrollData = nan(maxSamples, 1); hpitchData = nan(maxSamples, 1); hyawData = nan(maxSamples, 1);
            herrData = nan(maxSamples, 1);
            txData = nan(maxSamples, 1); tyData = nan(maxSamples, 1); tzData = nan(maxSamples, 1);
            trollData = nan(maxSamples, 1); tpitchData = nan(maxSamples, 1); tyawData = nan(maxSamples, 1);
            terrData = nan(maxSamples, 1);
            idx = 1;

            DrawFormattedText(win, sprintf('Perform task...\nPress %s when finished.', keyName), 'center', 'center', white);
            Screen('Flip', win);
            KbReleaseWait;

            % Capture initial position and orientation at start of recording
            [initHeadPos, initTorsoPos, initHeadEuler, initTorsoEuler, ~, ~] = OptiTrackBridge.GetDualData();
            initHeadYaw = initHeadEuler(3);
            initTorsoYaw = initTorsoEuler(3);

            while true
                [kd, ~, kc] = KbCheck;
                if kd && any(kc(escKey)), error('User Quit'); end
                if kd && any(kc(rKey)), error('Redo_Trial'); end 
                if kd && any(kc(targetKey)), break; end
                
                [currHeadPos, currTorsoPos, currHeadEuler, currTorsoEuler, currHeadErr, currTorsoErr] = OptiTrackBridge.GetDualData();
                
                if any(isnan(currHeadPos)) || any(isnan(currTorsoPos))
                    DrawFormattedText(win, '!!! TRACKING LOST !!!\nAdjust markers or move to visible area', 'center', 'center', [255 0 0]);
                    Screen('Flip', win);
                    WaitSecs(0.01);
                    continue;
                end
                
                if idx <= maxSamples
                    tData(idx) = GetSecs() - startTime;
                    hxData(idx) = currHeadPos(1); hyData(idx) = currHeadPos(2); hzData(idx) = currHeadPos(3);
                    hrollData(idx) = currHeadEuler(1); hpitchData(idx) = currHeadEuler(2); hyawData(idx) = currHeadEuler(3);
                    herrData(idx) = currHeadErr;
                    txData(idx) = currTorsoPos(1); tyData(idx) = currTorsoPos(2); tzData(idx) = currTorsoPos(3);
                    trollData(idx) = currTorsoEuler(1); tpitchData(idx) = currTorsoEuler(2); tyawData(idx) = currTorsoEuler(3);
                    terrData(idx) = currTorsoErr;
                    idx = idx + 1;                      
                end
                WaitSecs(0.01); 
            end
            
            n = idx - 1; t = tData(1:n);
            
            % Yaw displacement: final minus initial, with wraparound handling
            finalHeadYaw = mod(currHeadEuler(3) - initHeadYaw + 180, 360) - 180;
            finalTorsoYaw = mod(currTorsoEuler(3) - initTorsoYaw + 180, 360) - 180;

            % Displacement: final position minus initial position (xz plane)
            finalHeadWalk = sqrt((currHeadPos(1) - initHeadPos(1))^2 + (currHeadPos(3) - initHeadPos(3))^2);
            finalTorsoWalk = sqrt((currTorsoPos(1) - initTorsoPos(1))^2 + (currTorsoPos(3) - initTorsoPos(3))^2);
            
            headTrace.time = t; headTrace.x = hxData(1:n); headTrace.y = hyData(1:n); headTrace.z = hzData(1:n);
            headTrace.roll = hrollData(1:n); headTrace.pitch = hpitchData(1:n); headTrace.yaw = hyawData(1:n); headTrace.error = herrData(1:n);
            
            torsoTrace.time = t; torsoTrace.x = txData(1:n); torsoTrace.y = tyData(1:n); torsoTrace.z = tzData(1:n);
            torsoTrace.roll = trollData(1:n); torsoTrace.pitch = tpitchData(1:n); torsoTrace.yaw = tyawData(1:n); torsoTrace.error = terrData(1:n);
        end

        % =================================================================
        % INTERNAL UTILITIES
        % =================================================================
        function [headPos, torsoPos, headEuler, torsoEuler, headErr, torsoErr] = GetDualData()
            global OP_BRIDGE_STATE
            if OP_BRIDGE_STATE.IsDummy
                headPos = [0 0 0]; torsoPos = [0 0 0]; 
                headEuler = [0 0 0]; torsoEuler = [0 0 0]; 
                headErr = 0; torsoErr = 0;
                return; 
            end
            headPos = [NaN NaN NaN]; torsoPos = [NaN NaN NaN];
            headEuler = [NaN NaN NaN]; torsoEuler = [NaN NaN NaN];
            headErr = NaN; torsoErr = NaN;
            
            try
                data = OP_BRIDGE_STATE.NatNetClient.getFrame();
                if isempty(data), data = OP_BRIDGE_STATE.NatNetClient.GetLastFrameOfData(); end
                if isempty(data) || isempty(data.RigidBody), return; end
                
                for i = 1:data.RigidBody.Length
                    rb = data.RigidBody(i);
                    if rb.ID == OptiTrackBridge.HEAD_ID
                        headPos = [double(rb.x), double(rb.y), double(rb.z)];
                        [r, p, y] = OptiTrackBridge.QuatToEuler(double(rb.qw), double(rb.qx), double(rb.qy), double(rb.qz));
                        headEuler = [r, p, y];
                        headErr = double(rb.MeanError);
                    elseif rb.ID == OptiTrackBridge.TORSO_ID
                        torsoPos = [double(rb.x), double(rb.y), double(rb.z)];
                        [r, p, y] = OptiTrackBridge.QuatToEuler(double(rb.qw), double(rb.qx), double(rb.qy), double(rb.qz));
                        torsoEuler = [r, p, y];
                        torsoErr = double(rb.MeanError);
                    end
                end
            catch ME
                disp(['Data Extraction Error: ', ME.message]);
            end
        end

        function trace = EmptyTrace()
            trace.time  = []; trace.x = []; trace.y = []; trace.z = [];
            trace.roll  = []; trace.pitch = []; trace.yaw = []; trace.error = [];
        end

        function [roll, pitch, yaw] = QuatToEuler(qw, qx, qy, qz)
            t0 = 2.0 * (qw * qx + qy * qz);
            t1 = 1.0 - 2.0 * (qx * qx + qy * qy);
            roll = rad2deg(atan2(t0, t1));

            t2 = max(min(2.0 * (qw * qy - qz * qx), 1.0), -1.0);
            pitch = rad2deg(asin(t2));

            t3 = 2.0 * (qw * qz + qx * qy);
            t4 = 1.0 - 2.0 * (qy * qy + qz * qz);
            yaw = mod(rad2deg(atan2(t3, t4)), 360);
        end
    end
end
