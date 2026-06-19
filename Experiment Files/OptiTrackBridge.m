classdef OptiTrackBridge
    % OPTITRACKBRIDGE
    % Handles connection to OptiTrack Motive using the natnet class.
    % Uses timer-based polling at 120Hz for continuous collection.
    
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
        % CONNECT
        % =================================================================
        function success = Connect(subjectID)
            global OP_BRIDGE_STATE OP_EVENT_LOG OP_CONTINUOUS_BUFFER

            clear global OP_BRIDGE_STATE OP_EVENT_LOG OP_CONTINUOUS_BUFFER;
            global OP_BRIDGE_STATE OP_EVENT_LOG OP_CONTINUOUS_BUFFER

            % Initialize state struct
            OP_BRIDGE_STATE.NatNetClient = [];
            OP_BRIDGE_STATE.IsConnected = false;
            OP_BRIDGE_STATE.IsDummy = false;
            OP_BRIDGE_STATE.MotiveT0 = 0;
            
            % Initialize event log
            OP_EVENT_LOG.time  = [];
            OP_EVENT_LOG.trial = [];
            OP_EVENT_LOG.event = {};
            OP_EVENT_LOG.state = {};

            % Pre-allocate continuous buffer (high-performance arrays)
            nc = 500000;
            OP_CONTINUOUS_BUFFER.idx = 1;
            OP_CONTINUOUS_BUFFER.maxSamples = nc;
            OP_CONTINUOUS_BUFFER.time = NaN(nc, 1);
            OP_CONTINUOUS_BUFFER.hx = NaN(nc, 1);
            OP_CONTINUOUS_BUFFER.hy = NaN(nc, 1);
            OP_CONTINUOUS_BUFFER.hz = NaN(nc, 1);
            OP_CONTINUOUS_BUFFER.hroll = NaN(nc, 1);
            OP_CONTINUOUS_BUFFER.hpitch = NaN(nc, 1);
            OP_CONTINUOUS_BUFFER.hyaw = NaN(nc, 1);
            OP_CONTINUOUS_BUFFER.hErr = NaN(nc, 1);
            OP_CONTINUOUS_BUFFER.tx = NaN(nc, 1);
            OP_CONTINUOUS_BUFFER.ty = NaN(nc, 1);
            OP_CONTINUOUS_BUFFER.tz = NaN(nc, 1);
            OP_CONTINUOUS_BUFFER.troll = NaN(nc, 1);
            OP_CONTINUOUS_BUFFER.tpitch = NaN(nc, 1);
            OP_CONTINUOUS_BUFFER.tyaw = NaN(nc, 1);
            OP_CONTINUOUS_BUFFER.tErr = NaN(nc, 1);

            OP_BRIDGE_STATE.PollingTimer = [];  % Initialize timer field

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
                warning('OptiTrack:ConnectionFailed', 'Connection Failed: %s', ME.message);
                OP_BRIDGE_STATE.IsDummy = true;
                success = false;
            end
        end
        
        function Disconnect()
            global OP_BRIDGE_STATE OP_EVENT_LOG OP_CONTINUOUS_BUFFER
            if ~isempty(OP_BRIDGE_STATE) && ~OP_BRIDGE_STATE.IsDummy
                try 
                    OP_BRIDGE_STATE.NatNetClient.disconnect;
                catch
                end
            end
            clear global OP_BRIDGE_STATE OP_EVENT_LOG OP_CONTINUOUS_BUFFER;
        end

        % =================================================================
        % EVENT LOGGING
        % =================================================================
        function startEvent(trialNum, eventName)
            global OP_EVENT_LOG OP_BRIDGE_STATE OP_CONTINUOUS_BUFFER
            
            eventTime = 0;  % Default fallback

            if ~OP_BRIDGE_STATE.IsDummy && ~isempty(OP_BRIDGE_STATE.NatNetClient)
            data = OP_BRIDGE_STATE.NatNetClient.getFrame();
            if ~isempty(data) && ~isempty(data.Timestamp)
                if OP_BRIDGE_STATE.MotiveT0 > 0
                    % Use Motive T0 as reference
                    eventTime = double(data.Timestamp) - OP_BRIDGE_STATE.MotiveT0;
                elseif OP_CONTINUOUS_BUFFER.idx > 1  % At least one frame collected
                    % Fallback: use first continuous buffer frame as reference
                    firstFrameTime = OP_CONTINUOUS_BUFFER.time(1);
                    eventTime = double(data.Timestamp) - firstFrameTime;
                end
            end
            end
            
            i = length(OP_EVENT_LOG.time) + 1;
            OP_EVENT_LOG.time(i)  = eventTime;
            OP_EVENT_LOG.trial(i) = trialNum;
            OP_EVENT_LOG.event{i} = eventName;
            OP_EVENT_LOG.state{i} = 'START';
        end

        function stopEvent(trialNum, eventName)
            global OP_EVENT_LOG OP_BRIDGE_STATE OP_CONTINUOUS_BUFFER
            
            eventTime = 0;  % Default fallback
            
            if ~OP_BRIDGE_STATE.IsDummy && ~isempty(OP_BRIDGE_STATE.NatNetClient)
            data = OP_BRIDGE_STATE.NatNetClient.getFrame();
            if ~isempty(data) && ~isempty(data.Timestamp)
                if OP_BRIDGE_STATE.MotiveT0 > 0
                    % Use Motive T0 as reference
                    eventTime = double(data.Timestamp) - OP_BRIDGE_STATE.MotiveT0;
                elseif OP_CONTINUOUS_BUFFER.idx > 1  % At least one frame collected
                    % Fallback: use first continuous buffer frame as reference
                    firstFrameTime = OP_CONTINUOUS_BUFFER.time(1);
                    eventTime = double(data.Timestamp) - firstFrameTime;
                end
            end
            end
            
            i = length(OP_EVENT_LOG.time) + 1;
            OP_EVENT_LOG.time(i)  = eventTime;
            OP_EVENT_LOG.trial(i) = trialNum;
            OP_EVENT_LOG.event{i} = eventName;
            OP_EVENT_LOG.state{i} = 'STOP';
        end

        % =================================================================
        % DUMMY START/STOP RECORDING
        % =================================================================
        function StartRecording()
        end

        function [headTrace, torsoTrace] = StopRecording()
            % Stub in polling version (task traces built directly in task functions)
            % Included for API compatibility; actual recording happens in PassiveTrack, etc.
            headTrace.time = []; headTrace.x = []; headTrace.y = []; headTrace.z = [];
            headTrace.roll = []; headTrace.pitch = []; headTrace.yaw = []; headTrace.error = [];
            torsoTrace.time = []; torsoTrace.x = []; torsoTrace.y = []; torsoTrace.z = [];
            torsoTrace.roll = []; torsoTrace.pitch = []; torsoTrace.yaw = []; torsoTrace.error = [];
        end

        % =================================================================
        % START CONTINUOUS COLLECTION (Timer-based at 120Hz)
        % =================================================================
        function StartContinuousCollection()
            global OP_BRIDGE_STATE OP_CONTINUOUS_BUFFER
            
            if OP_BRIDGE_STATE.IsDummy, return; end
            
            % Reset index to beginning
            OP_CONTINUOUS_BUFFER.idx = 1;
            
            % Create and start polling timer at 120Hz
            OP_BRIDGE_STATE.PollingTimer = timer(...
                'ExecutionMode', 'fixedRate', ...
                'Period', 1/120, ...
                'TimerFcn', @(~,~) OptiTrackBridge.PollFrame());
            
            start(OP_BRIDGE_STATE.PollingTimer);
            fprintf('>>> Continuous polling started at 120Hz\n');
        end

        % =================================================================
        % STOP CONTINUOUS COLLECTION
        % =================================================================
        function StopContinuousCollection()
            global OP_BRIDGE_STATE
            
            if ~isempty(OP_BRIDGE_STATE) && isfield(OP_BRIDGE_STATE, 'PollingTimer')
                if ~isempty(OP_BRIDGE_STATE.PollingTimer) && isvalid(OP_BRIDGE_STATE.PollingTimer)
                    stop(OP_BRIDGE_STATE.PollingTimer);
                    delete(OP_BRIDGE_STATE.PollingTimer);
                end
                OP_BRIDGE_STATE.PollingTimer = [];
            end
            fprintf('>>> Continuous polling stopped\n');
        end

        % =================================================================
        % POLL SINGLE FRAME (Called by timer at 120Hz)
        % =================================================================
        function PollFrame()
            global OP_BRIDGE_STATE OP_CONTINUOUS_BUFFER
            
            try
                data = OP_BRIDGE_STATE.NatNetClient.getFrame();
                if isempty(data) || isempty(data.RigidBody), return; end
                
                [headPos, torsoPos, headEuler, torsoEuler, headErr, torsoErr] = OptiTrackBridge.GetDualData();
                
                % Write to continuous buffer using Motive frame timestamp
                cidx = OP_CONTINUOUS_BUFFER.idx;
                if cidx <= OP_CONTINUOUS_BUFFER.maxSamples
                    OP_CONTINUOUS_BUFFER.time(cidx) = double(data.Timestamp);
                    OP_CONTINUOUS_BUFFER.hx(cidx) = headPos(1);
                    OP_CONTINUOUS_BUFFER.hy(cidx) = headPos(2);
                    OP_CONTINUOUS_BUFFER.hz(cidx) = headPos(3);
                    OP_CONTINUOUS_BUFFER.hroll(cidx) = headEuler(1);
                    OP_CONTINUOUS_BUFFER.hpitch(cidx) = headEuler(2);
                    OP_CONTINUOUS_BUFFER.hyaw(cidx) = headEuler(3);
                    OP_CONTINUOUS_BUFFER.hErr(cidx) = headErr;
                    OP_CONTINUOUS_BUFFER.tx(cidx) = torsoPos(1);
                    OP_CONTINUOUS_BUFFER.ty(cidx) = torsoPos(2);
                    OP_CONTINUOUS_BUFFER.tz(cidx) = torsoPos(3);
                    OP_CONTINUOUS_BUFFER.troll(cidx) = torsoEuler(1);
                    OP_CONTINUOUS_BUFFER.tpitch(cidx) = torsoEuler(2);
                    OP_CONTINUOUS_BUFFER.tyaw(cidx) = torsoEuler(3);
                    OP_CONTINUOUS_BUFFER.tErr(cidx) = torsoErr;
                    OP_CONTINUOUS_BUFFER.idx = cidx + 1;
                end
            catch
                % Silently skip frame on error
            end
        end

        % =================================================================
        % SAVE CONTINUOUS SESSION DATA
        % =================================================================
        function SaveContinuous(filename)
            global OP_CONTINUOUS_BUFFER OP_EVENT_LOG OP_BRIDGE_STATE
            
            n = OP_CONTINUOUS_BUFFER.idx - 1;
            if n < 1
                warning('Continuous buffer is empty.');
                return;
            end
            
            % --- HEAD TRACE ---
            headTrace.time = OP_CONTINUOUS_BUFFER.time(1:n);
            headTrace.x = OP_CONTINUOUS_BUFFER.hx(1:n);
            headTrace.y = OP_CONTINUOUS_BUFFER.hy(1:n);
            headTrace.z = OP_CONTINUOUS_BUFFER.hz(1:n);
            headTrace.roll = OP_CONTINUOUS_BUFFER.hroll(1:n);
            headTrace.pitch = OP_CONTINUOUS_BUFFER.hpitch(1:n);
            headTrace.yaw = OP_CONTINUOUS_BUFFER.hyaw(1:n);
            headTrace.error = OP_CONTINUOUS_BUFFER.hErr(1:n);
            
            % --- TORSO TRACE ---
            torsoTrace.time = OP_CONTINUOUS_BUFFER.time(1:n);
            torsoTrace.x = OP_CONTINUOUS_BUFFER.tx(1:n);
            torsoTrace.y = OP_CONTINUOUS_BUFFER.ty(1:n);
            torsoTrace.z = OP_CONTINUOUS_BUFFER.tz(1:n);
            torsoTrace.roll = OP_CONTINUOUS_BUFFER.troll(1:n);
            torsoTrace.pitch = OP_CONTINUOUS_BUFFER.tpitch(1:n);
            torsoTrace.yaw = OP_CONTINUOUS_BUFFER.tyaw(1:n);
            torsoTrace.error = OP_CONTINUOUS_BUFFER.tErr(1:n);
            
            % Normalize time
            if OP_BRIDGE_STATE.MotiveT0 > 0
                headTrace.time = headTrace.time - OP_BRIDGE_STATE.MotiveT0;
                torsoTrace.time = torsoTrace.time - OP_BRIDGE_STATE.MotiveT0;
            elseif n >= 1
                headTrace.time = headTrace.time - headTrace.time(1);
                torsoTrace.time = torsoTrace.time - torsoTrace.time(1);
            end
            
            EventLog = table(OP_EVENT_LOG.time', OP_EVENT_LOG.trial', ...
                OP_EVENT_LOG.event', OP_EVENT_LOG.state', ...
                'VariableNames', {'Time', 'Trial', 'Event', 'State'});
            
            save(filename, 'headTrace', 'torsoTrace', 'EventLog', '-v7.3');
            fprintf('Continuous data saved: %s  (%d frames, %.1f min)\n', ...
                filename, n, headTrace.time(end) / 60);
        end

        % =================================================================
        % EMPTY TRACE
        % =================================================================
        function trace = EmptyTrace()
            trace.time  = []; trace.x = []; trace.y = []; trace.z = [];
            trace.roll  = []; trace.pitch = []; trace.yaw = []; trace.error = [];
        end

        % ---------------------------------------------------------
        % WAIT FOR WALK END / ORIGIN
        % ---------------------------------------------------------
        function [distWalkedTorso, distWalkedHead, headDistFromCenter, torsoDistFromCenter, headTrace, torsoTrace] = WaitForWalkEnd(headID, torsoID, win, tolerance)
            global OP_BRIDGE_STATE OP_CONTINUOUS_BUFFER PAUSE_ACTIVE TL t PAUSE_CALLED trueTrial
            if nargin < 4, tolerance = 0.10; end 
            
            if OP_BRIDGE_STATE.IsDummy
                DrawFormattedText(win, 'DUMMY MODE: Press "x" to simulate walking.', 'center', 'center', [255 255 0]);
                Screen('Flip', win);
                while true
                    [kd, ~, kc] = KbCheck;
                    if kd && kc(KbName('ESCAPE')), error('User Quit'); end
                    if kd && kc(KbName('r')), error('Redo_Trial'); end                        
                    if ~PAUSE_ACTIVE && kd && kc(KbName('x')), WaitSecs(0.3); break; end
                    if kd && any(kc(KbName('p')))
                        if ~PAUSE_ACTIVE
                            PAUSE_ACTIVE = true;
                            PAUSE_CALLED = "TRUE"; 
                            if ~isempty(TL), TL.pauseIndicatorStart(65, trueTrial, 'PauseStart'); end
                            OptiTrackBridge.startEvent(trueTrial, 'Pause');
                            disp('DUMMY PAUSE: Activated'); 
                        else
                            PAUSE_ACTIVE = false;
                            OptiTrackBridge.stopEvent(trueTrial, 'Pause');
                            if ~isempty(TL), TL.pauseIndicatorEnd(65, trueTrial, 'PauseResume'); end
                            disp('DUMMY PAUSE: Deactivated');
                        end
                        WaitSecs(0.3);  % debounce
                    end
                    
                end
                distWalkedTorso = 2.0; distWalkedHead = 2.0;
                headDistFromCenter = 0.0; torsoDistFromCenter = 0.0;
                headTrace = OptiTrackBridge.EmptyTrace();
                torsoTrace = OptiTrackBridge.EmptyTrace();
                return;
            end

            startTime = GetSecs();
            
            % Wait for initial valid frame to establish start positions
            startTorsoPos = [NaN NaN NaN]; startHeadPos = [NaN NaN NaN];
            while any(isnan(startTorsoPos)) || any(isnan(startHeadPos))
                [startHeadPos, startTorsoPos, ~, ~, ~, ~] = OptiTrackBridge.GetDualData();
                WaitSecs(0.01);
            end
            
            white = WhiteIndex(win);
            Screen('TextSize', win, 40);

            maxSamples = 10000; 
            tData = nan(maxSamples, 1);
            hxData = nan(maxSamples, 1); hyData = nan(maxSamples, 1); hzData = nan(maxSamples, 1);
            hrollData = nan(maxSamples, 1); hpitchData = nan(maxSamples, 1); hyawData = nan(maxSamples, 1);
            herrData = nan(maxSamples, 1);
            txData = nan(maxSamples, 1); tyData = nan(maxSamples, 1); tzData = nan(maxSamples, 1);
            trollData = nan(maxSamples, 1); tpitchData = nan(maxSamples, 1); tyawData = nan(maxSamples, 1);
            terrData = nan(maxSamples, 1);
            idx = 1;

            while true
                [kd, ~, kc] = KbCheck;
                if kd && kc(KbName('ESCAPE')), error('User Quit'); end
                if kd && kc(KbName('r')), error('Redo_Trial'); end 
                % ===== PAUSE TOGGLE WITH MEG + EVENT LOGGING (NON-INTERRUPTING) =====
                if kd && kc(KbName('p'))
                    if ~PAUSE_ACTIVE
                        % PAUSE: Log to MEG and OptiTrack
                        PAUSE_ACTIVE = true;
                        PAUSE_CALLED = "TRUE";
                        if ~isempty(TL), TL.pauseIndicatorStart(65, trueTrial, 'PauseStart'); end
                        OptiTrackBridge.startEvent(trueTrial, 'Pause');
                    else
                        % RESUME: Log to MEG and OptiTrack
                        PAUSE_ACTIVE = false;
                        OptiTrackBridge.stopEvent(trueTrial, 'Pause');
                        if ~isempty(TL), TL.pauseIndicatorEnd(65, trueTrial, 'PauseResume'); end
                    end
                    WaitSecs(0.3);  % debounce
                end
                % ===================================================================

                % Pull data in a single synchronized call
                [currHeadPos, currTorsoPos, currHeadEuler, currTorsoEuler, currHeadErr, currTorsoErr, frameTimestamp] = OptiTrackBridge.GetDualData();

                if any(isnan(currHeadPos)) || any(isnan(currTorsoPos))
                    DrawFormattedText(win, '!!! TRACKING LOST !!!\nAdjust markers or move to visible area', 'center', 'center', [255 0 0]);
                    Screen('Flip', win);
                    WaitSecs(0.01);
                    continue; 
                end
                
                zTarget = 0.05;
                distToCenter = sqrt(currHeadPos(1)^2 + (currHeadPos(3) - zTarget)^2);
                inSemiCircle = (distToCenter < tolerance) && (currHeadPos(3) >= zTarget);
                
                if idx <= maxSamples
                    % Use global reference: MotiveT0 or first continuous frame
                    if OP_BRIDGE_STATE.MotiveT0 > 0
                        tData(idx) = frameTimestamp - OP_BRIDGE_STATE.MotiveT0;
                    elseif OP_CONTINUOUS_BUFFER.idx > 1
                        tData(idx) = frameTimestamp - OP_CONTINUOUS_BUFFER.time(1);
                    else
                        tData(idx) = frameTimestamp;
                    end
                    hxData(idx) = currHeadPos(1); hyData(idx) = currHeadPos(2); hzData(idx) = currHeadPos(3);
                    hrollData(idx) = currHeadEuler(1); hpitchData(idx) = currHeadEuler(2); hyawData(idx) = currHeadEuler(3);
                    herrData(idx) = currHeadErr;
                    txData(idx) = currTorsoPos(1); tyData(idx) = currTorsoPos(2); tzData(idx) = currTorsoPos(3);
                    trollData(idx) = currTorsoEuler(1); tpitchData(idx) = currTorsoEuler(2); tyawData(idx) = currTorsoEuler(3);
                    terrData(idx) = currTorsoErr;
                    idx = idx + 1;                      
                end
                
                % ===== DISPLAY: Check pause status =====
                if PAUSE_ACTIVE
                    pauseStatus = ' [PAUSED]';
                    pauseColor = [255 255 0];
                else
                    pauseStatus = '';
                    pauseColor = white;
                end
                % =========================================
                
                msg = sprintf('Walk to Start\nDistance: %.2fm%s', distToCenter, pauseStatus);
                DrawFormattedText(win, msg, 'center', 'center', pauseColor);
                
                if inSemiCircle
                    color = [0 255 0];
                else
                    color = [255 0 0];
                end
                
                centeredRect = CenterRectOnPointd([0 0 50 50], 960, 600);
                Screen('FillArc', win, color, centeredRect + [0 100 0 100], 270, 180);
                Screen('Flip', win); 

                % ===== GOAL CHECK: Only advance if NOT paused =====
                if ~PAUSE_ACTIVE && inSemiCircle
                    DrawFormattedText(win, 'Hold Position...', 'center', 'center', [0 255 0]);
                    Screen('Flip', win);
                    break;
                end
                % ==================================================
            end
            
            n = idx - 1; t = tData(1:n);
            
            headTrace.time = t; headTrace.x = hxData(1:n); headTrace.y = hyData(1:n); headTrace.z = hzData(1:n);
            headTrace.roll = hrollData(1:n); headTrace.pitch = hpitchData(1:n); headTrace.yaw = hyawData(1:n); headTrace.error = herrData(1:n);

            torsoTrace.time = t; torsoTrace.x = txData(1:n); torsoTrace.y = tyData(1:n); torsoTrace.z = tzData(1:n);
            torsoTrace.roll = trollData(1:n); torsoTrace.pitch = tpitchData(1:n); torsoTrace.yaw = tyawData(1:n); torsoTrace.error = terrData(1:n);

            distWalkedTorso = sqrt((currTorsoPos(1) - startTorsoPos(1))^2 + (currTorsoPos(3) - startTorsoPos(3))^2);
            distWalkedHead = sqrt((currHeadPos(1) - startHeadPos(1))^2 + (currHeadPos(3) - startHeadPos(3))^2);

            headDistFromCenter = sqrt(currHeadPos(1)^2 + currHeadPos(3)^2);
            torsoDistFromCenter = sqrt(currTorsoPos(1)^2 + currTorsoPos(3)^2);
        end

        % ---------------------------------------------------------
        % WAIT FOR ROTATION DUAL
        % ---------------------------------------------------------
        function [startHead, startTorso, finalHead, finalTorso, headTrace, torsoTrace] = WaitForRotationDual(headID, torsoID, targetDeg, win, dirCode)
            global OP_BRIDGE_STATE OP_CONTINUOUS_BUFFER PAUSE_ACTIVE TL t PAUSE_CALLED trueTrial
            
            if OP_BRIDGE_STATE.IsDummy
                DrawFormattedText(win, 'DUMMY MODE: Press "x" to simulate turning.', 'center', 'center', [255 255 0]);
                Screen('Flip', win);
                while true
                    [kd, ~, kc] = KbCheck;
                    if kd && kc(KbName('ESCAPE')), error('User Quit'); end
                    if kd && kc(KbName('r')), error('Redo_Trial'); end
                    if ~PAUSE_ACTIVE && kd && kc(KbName('x')), WaitSecs(0.3); break; end
                    if kd && any(kc(KbName('p')))
                        if ~PAUSE_ACTIVE
                            PAUSE_ACTIVE = true;
                            PAUSE_CALLED = "TRUE";
                            if ~isempty(TL), TL.pauseIndicatorStart(65, trueTrial, 'PauseStart'); end
                            OptiTrackBridge.startEvent(trueTrial, 'Pause');
                            disp('DUMMY PAUSE: Activated'); 
                        else
                            PAUSE_ACTIVE = false;
                            OptiTrackBridge.stopEvent(trueTrial, 'Pause');
                            if ~isempty(TL), TL.pauseIndicatorEnd(65, trueTrial, 'PauseResume'); end
                            disp('DUMMY PAUSE: Deactivated');
                        end
                        WaitSecs(0.3);  % debounce
                    end
                end
                startHead = 0; startTorso = 0; finalHead = targetDeg; finalTorso = targetDeg;
                headTrace = OptiTrackBridge.EmptyTrace();
                torsoTrace = OptiTrackBridge.EmptyTrace();
                return;
            end

            rotationCorrect = false;
            while ~rotationCorrect
                white = WhiteIndex(win);

                % Ensure baseline start orientation
                startHeadEuler = [NaN NaN NaN]; startTorsoEuler = [NaN NaN NaN];
                while any(isnan(startHeadEuler)) || any(isnan(startTorsoEuler))
                    [~, ~, startHeadEuler, startTorsoEuler, ~, ~] = OptiTrackBridge.GetDualData();
                    WaitSecs(0.01);
                end
                
                startHead = startHeadEuler(3);
                startTorso = startTorsoEuler(3);
                prevTorsoYaw = startTorso; 
                accumulatedTurn = 0;       
                startTime = GetSecs();     
                
                maxSamples = 20000;
                tData = nan(maxSamples, 1);
                hxData = nan(maxSamples, 1); hyData = nan(maxSamples, 1); hzData = nan(maxSamples, 1);
                hrollData = nan(maxSamples, 1); hpitchData = nan(maxSamples, 1); hyawData = nan(maxSamples, 1);
                herrData = nan(maxSamples, 1);
                txData = nan(maxSamples, 1); tyData = nan(maxSamples, 1); tzData = nan(maxSamples, 1);
                trollData = nan(maxSamples, 1); tpitchData = nan(maxSamples, 1); tyawData = nan(maxSamples, 1);
                terrData = nan(maxSamples, 1);
                idx = 1;      
                
                KbReleaseWait;
                
                while true
                    [kd, ~, kc] = KbCheck;
                    if kd && kc(KbName('ESCAPE')), error('User Quit'); end
                    if kd && kc(KbName('r')), error('Redo_Trial'); end 
                    % ===== PAUSE TOGGLE WITH MEG + EVENT LOGGING (NON-INTERRUPTING) =====
                    if kd && kc(KbName('p'))
                        if ~PAUSE_ACTIVE
                            % PAUSE: Log to MEG and OptiTrack
                            PAUSE_ACTIVE = true;
                            PAUSE_CALLED = "TRUE";
                            if ~isempty(TL), TL.pauseIndicatorStart(65, trueTrial, 'PauseStart'); end
                            OptiTrackBridge.startEvent(trueTrial, 'Pause');
                        else
                            % RESUME: Log to MEG and OptiTrack
                            PAUSE_ACTIVE = false;
                            OptiTrackBridge.stopEvent(trueTrial, 'Pause');
                            if ~isempty(TL), TL.pauseIndicatorEnd(65, trueTrial, 'PauseResume'); end
                        end
                        WaitSecs(0.3);  % debounce
                    end
                    % ===================================================================
                    
                    [currHeadPos, currTorsoPos, currHeadEuler, currTorsoEuler, currHeadErr, currTorsoErr, frameTimestamp] = OptiTrackBridge.GetDualData();
                    
                    if any(isnan(currTorsoEuler)) || any(isnan(currHeadEuler))
                       DrawFormattedText(win, '!!! TRACKING LOST !!!\nAdjust markers or move to visible area', 'center', 'center', [255 0 0]);
                       Screen('Flip', win);
                       WaitSecs(0.01);
                       continue;
                    end

                    if idx <= maxSamples
                        % Use global reference: MotiveT0 or first continuous frame
                        if OP_BRIDGE_STATE.MotiveT0 > 0
                            tData(idx) = frameTimestamp - OP_BRIDGE_STATE.MotiveT0;
                        elseif OP_CONTINUOUS_BUFFER.idx > 1
                            tData(idx) = frameTimestamp - OP_CONTINUOUS_BUFFER.time(1);
                        else
                            tData(idx) = frameTimestamp;
                        end
                        hxData(idx) = currHeadPos(1); hyData(idx) = currHeadPos(2); hzData(idx) = currHeadPos(3);
                        hrollData(idx) = currHeadEuler(1); hpitchData(idx) = currHeadEuler(2); hyawData(idx) = currHeadEuler(3);
                        herrData(idx) = currHeadErr;
                        txData(idx) = currTorsoPos(1); tyData(idx) = currTorsoPos(2); tzData(idx) = currTorsoPos(3);
                        trollData(idx) = currTorsoEuler(1); tpitchData(idx) = currTorsoEuler(2); tyawData(idx) = currTorsoEuler(3);
                        terrData(idx) = currTorsoErr;
                        idx = idx + 1;                      
                    end
                    
                    currTorsoYaw = currTorsoEuler(3);
                    delta = currTorsoYaw - prevTorsoYaw;
                    if delta > 180,  delta = delta - 360; end
                    if delta < -180, delta = delta + 360; end
                    accumulatedTurn = accumulatedTurn + delta; 
                    prevTorsoYaw = currTorsoYaw;

                    % ===== DISPLAY: Check pause status =====
                    if PAUSE_ACTIVE
                        pauseStatus = ' [PAUSED]';
                        pauseColor = [255 255 0];
                    else
                        pauseStatus = '';
                        pauseColor = white;
                    end
                    % =========================================
                    
                    remaining = targetDeg - abs(accumulatedTurn);
                    msg = sprintf('Turn Body: %.1f / %.1f\nRemaining: %.1f%s', abs(accumulatedTurn), targetDeg, max(0, remaining), pauseStatus);
                    DrawFormattedText(win, msg, 'center', 'center', pauseColor);
                    Screen('Flip', win);

                    % ===== GOAL CHECK: Only complete if NOT paused =====
                    if ~PAUSE_ACTIVE && abs(accumulatedTurn) >= targetDeg
                        turnedLeftCorrectly  = strcmpi(dirCode, 'L') && (accumulatedTurn >= targetDeg);
                        turnedRightCorrectly = strcmpi(dirCode, 'R') && (accumulatedTurn <= -targetDeg);
                        
                        if turnedLeftCorrectly || turnedRightCorrectly
                            DrawFormattedText(win, 'DONE! STOP.', 'center', 'center', [0 255 0]);
                            Screen('Flip', win);
                            rotationCorrect = true;
                            break;
                        else
                            DrawFormattedText(win, 'INCORRECT DIRECTION\nTrying again...', 'center', 'center', [255 0 0]);
                            Screen('Flip', win);
                            WaitSecs(2.0);
                            break;
                        end
                    end
                    % ===================================================
                end
            end
            
            n = idx - 1; t = tData(1:n);
            
            finalHead = currHeadEuler(3); finalTorso = currTorsoEuler(3);
            
            headTrace.time = t; headTrace.x = hxData(1:n); headTrace.y = hyData(1:n); headTrace.z = hzData(1:n);
            headTrace.roll = hrollData(1:n); headTrace.pitch = hpitchData(1:n); headTrace.yaw = hyawData(1:n); headTrace.error = herrData(1:n);
            
            torsoTrace.time = t; torsoTrace.x = txData(1:n); torsoTrace.y = tyData(1:n); torsoTrace.z = tzData(1:n);
            torsoTrace.roll = trollData(1:n); torsoTrace.pitch = tpitchData(1:n); torsoTrace.yaw = tyawData(1:n); torsoTrace.error = terrData(1:n);
        end

        % ---------------------------------------------------------
        % RECORD UNTIL KEY
        % ---------------------------------------------------------
        function [finalHead, finalTorso, headTrace, torsoTrace] = RecordUntilKey(headID, torsoID, keyName, win)
            global OP_BRIDGE_STATE OP_CONTINUOUS_BUFFER PAUSE_ACTIVE TL t PAUSE_CALLED trueTrial
            
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
                    if ~PAUSE_ACTIVE && kd && (any(kc(targetKey)) || any(kc(xKey)))
                        WaitSecs(0.3); break; 
                    end
                    if kd && any(kc(KbName('p')))
                        if ~PAUSE_ACTIVE
                            PAUSE_ACTIVE = true;
                            PAUSE_CALLED = "TRUE"; 
                            if ~isempty(TL), TL.pauseIndicatorStart(65, trueTrial, 'PauseStart'); end
                            OptiTrackBridge.startEvent(trueTrial, 'Pause');
                            disp('DUMMY PAUSE: Activated'); 
                        else
                            PAUSE_ACTIVE = false;
                            OptiTrackBridge.stopEvent(trueTrial, 'Pause');
                            if ~isempty(TL), TL.pauseIndicatorEnd(65, trueTrial, 'PauseResume'); end
                            disp('DUMMY PAUSE: Deactivated');
                        end
                        WaitSecs(0.3);  % debounce
                    end
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

            while true
                [kd, ~, kc] = KbCheck;
                if kd && any(kc(escKey)), error('User Quit'); end
                if kd && any(kc(rKey)), error('Redo_Trial'); end 
                % ===== PAUSE TOGGLE WITH MEG + EVENT LOGGING (NON-INTERRUPTING) =====
                if kd && any(kc(KbName('p')))
                    if ~PAUSE_ACTIVE
                        % PAUSE: Log to MEG and OptiTrack
                        PAUSE_ACTIVE = true;
                        PAUSE_CALLED = "TRUE";
                        if ~isempty(TL), TL.pauseIndicatorStart(65, trueTrial, 'PauseStart'); end
                        OptiTrackBridge.startEvent(trueTrial, 'Pause');
                    else
                        % RESUME: Log to MEG and OptiTrack
                        PAUSE_ACTIVE = false;
                        OptiTrackBridge.stopEvent(trueTrial, 'Pause');
                        if ~isempty(TL), TL.pauseIndicatorEnd(65, trueTrial, 'PauseResume'); end
                    end
                    WaitSecs(0.3);  % debounce
                end
                % ===================================================================
                if ~PAUSE_ACTIVE && kd && any(kc(targetKey)), break; end
                
                [currHeadPos, currTorsoPos, currHeadEuler, currTorsoEuler, currHeadErr, currTorsoErr, frameTimestamp] = OptiTrackBridge.GetDualData();
                
                if any(isnan(currHeadPos)) || any(isnan(currTorsoPos))
                    DrawFormattedText(win, '!!! TRACKING LOST !!!\nAdjust markers or move to visible area', 'center', 'center', [255 0 0]);
                    Screen('Flip', win);
                    WaitSecs(0.01);
                    continue;
                end
                
                if idx <= maxSamples
                    % Use global reference: MotiveT0 or first continuous frame
                    if OP_BRIDGE_STATE.MotiveT0 > 0
                        tData(idx) = frameTimestamp - OP_BRIDGE_STATE.MotiveT0;
                    elseif OP_CONTINUOUS_BUFFER.idx > 1
                        tData(idx) = frameTimestamp - OP_CONTINUOUS_BUFFER.time(1);
                    else
                        tData(idx) = frameTimestamp;
                    end
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
            
            finalHead = currHeadEuler(3); finalTorso = currTorsoEuler(3);
            
            headTrace.time = t; headTrace.x = hxData(1:n); headTrace.y = hyData(1:n); headTrace.z = hzData(1:n);
            headTrace.roll = hrollData(1:n); headTrace.pitch = hpitchData(1:n); headTrace.yaw = hyawData(1:n); headTrace.error = herrData(1:n);
            
            torsoTrace.time = t; torsoTrace.x = txData(1:n); torsoTrace.y = tyData(1:n); torsoTrace.z = tzData(1:n);
            torsoTrace.roll = trollData(1:n); torsoTrace.pitch = tpitchData(1:n); torsoTrace.yaw = tyawData(1:n); torsoTrace.error = terrData(1:n);
        end

        % ---------------------------------------------------------
        % PASSIVE TRACK
        % ---------------------------------------------------------
        function [headTrace, torsoTrace] = PassiveTrack(headID, torsoID, durationSecs)
            global OP_BRIDGE_STATE OP_CONTINUOUS_BUFFER
            
            if OP_BRIDGE_STATE.IsDummy
                WaitSecs(durationSecs);
                headTrace = OptiTrackBridge.EmptyTrace();
                torsoTrace = OptiTrackBridge.EmptyTrace();
                return;
            end
            
            startTime = GetSecs();
            maxSamples = 30000;
            
            tData = nan(maxSamples, 1);
            hxData = nan(maxSamples, 1); hyData = nan(maxSamples, 1); hzData = nan(maxSamples, 1);
            hrollData = nan(maxSamples, 1); hpitchData = nan(maxSamples, 1); hyawData = nan(maxSamples, 1);
            herrData = nan(maxSamples, 1);
            txData = nan(maxSamples, 1); tyData = nan(maxSamples, 1); tzData = nan(maxSamples, 1);
            trollData = nan(maxSamples, 1); tpitchData = nan(maxSamples, 1); tyawData = nan(maxSamples, 1);
            terrData = nan(maxSamples, 1);
            idx = 1;
            
            deadline = GetSecs() + durationSecs;
            while GetSecs() < deadline
                [kd, ~, kc] = KbCheck;
                if kd && kc(KbName('ESCAPE')), error('User Quit'); end
                
                [currHeadPos, currTorsoPos, currHeadEuler, currTorsoEuler, currHeadErr, currTorsoErr, frameTimestamp] = OptiTrackBridge.GetDualData();
                
                if ~any(isnan(currHeadPos)) && ~any(isnan(currTorsoPos)) && idx <= maxSamples
                    % Use global reference: MotiveT0 or first continuous frame
                    if OP_BRIDGE_STATE.MotiveT0 > 0
                        tData(idx) = frameTimestamp - OP_BRIDGE_STATE.MotiveT0;
                    elseif OP_CONTINUOUS_BUFFER.idx > 1
                        tData(idx) = frameTimestamp - OP_CONTINUOUS_BUFFER.time(1);
                    else
                        tData(idx) = frameTimestamp;
                    end
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
            
            n = idx - 1;
            if n > 0
                t = tData(1:n);
                headTrace.time = t; headTrace.x = hxData(1:n); headTrace.y = hyData(1:n); headTrace.z = hzData(1:n);
                headTrace.roll = hrollData(1:n); headTrace.pitch = hpitchData(1:n); headTrace.yaw = hyawData(1:n); headTrace.error = herrData(1:n);
                
                torsoTrace.time = t; torsoTrace.x = txData(1:n); torsoTrace.y = tyData(1:n); torsoTrace.z = tzData(1:n);
                torsoTrace.roll = trollData(1:n); torsoTrace.pitch = tpitchData(1:n); torsoTrace.yaw = tyawData(1:n); torsoTrace.error = terrData(1:n);
            else
                headTrace = OptiTrackBridge.EmptyTrace();
                torsoTrace = OptiTrackBridge.EmptyTrace();
            end
        end

        % ---------------------------------------------------------
        % WAIT FOR REALIGNMENT (Stationary center check with traces)
        % ---------------------------------------------------------
        function [headTrace, torsoTrace] = WaitForRealignment(headID, torsoID, centerThreshold, requiredTime, win)
            global OP_BRIDGE_STATE OP_CONTINUOUS_BUFFER
            
            if OP_BRIDGE_STATE.IsDummy
                WaitSecs(requiredTime);
                headTrace = OptiTrackBridge.EmptyTrace();
                torsoTrace = OptiTrackBridge.EmptyTrace();
                return;
            end
            
            white = WhiteIndex(win);
            isWarningOnScreen = false;
            stationaryStartTime = GetSecs();
            
            maxSamples = 10000;
            tData = nan(maxSamples, 1);
            hxData = nan(maxSamples, 1); hyData = nan(maxSamples, 1); hzData = nan(maxSamples, 1);
            hrollData = nan(maxSamples, 1); hpitchData = nan(maxSamples, 1); hyawData = nan(maxSamples, 1);
            herrData = nan(maxSamples, 1);
            txData = nan(maxSamples, 1); tyData = nan(maxSamples, 1); tzData = nan(maxSamples, 1);
            trollData = nan(maxSamples, 1); tpitchData = nan(maxSamples, 1); tyawData = nan(maxSamples, 1);
            terrData = nan(maxSamples, 1);
            idx = 1;
            

            
            while (GetSecs() - stationaryStartTime) < requiredTime
                
                [kd, ~, kc] = KbCheck;
                if kd && kc(KbName('ESCAPE')), error('User Quit'); end
                if kd && kc(KbName('r')), error('Redo_Trial'); end
                
                [currHeadPos, currTorsoPos, currHeadEuler, currTorsoEuler, currHeadErr, currTorsoErr, frameTimestamp] = OptiTrackBridge.GetDualData();
                
                if any(isnan(currHeadPos)) || any(isnan(currTorsoPos))

                    
                    WaitSecs(0.01);
                    continue;
                end
                

                
                if idx <= maxSamples
                    if OP_BRIDGE_STATE.MotiveT0 > 0
                        tData(idx) = frameTimestamp - OP_BRIDGE_STATE.MotiveT0;
                    elseif OP_CONTINUOUS_BUFFER.idx > 1
                        tData(idx) = frameTimestamp - OP_CONTINUOUS_BUFFER.time(1);
                    else
                        tData(idx) = frameTimestamp;
                    end
                    hxData(idx) = currHeadPos(1); hyData(idx) = currHeadPos(2); hzData(idx) = currHeadPos(3);
                    hrollData(idx) = currHeadEuler(1); hpitchData(idx) = currHeadEuler(2); hyawData(idx) = currHeadEuler(3);
                    herrData(idx) = currHeadErr;
                    txData(idx) = currTorsoPos(1); tyData(idx) = currTorsoPos(2); tzData(idx) = currTorsoPos(3);
                    trollData(idx) = currTorsoEuler(1); tpitchData(idx) = currTorsoEuler(2); tyawData(idx) = currTorsoEuler(3);
                    terrData(idx) = currTorsoErr;
                    idx = idx + 1;
                end
                
                distFromCenter = sqrt(currTorsoPos(1)^2 + currTorsoPos(3)^2);
                
                if distFromCenter > centerThreshold
                    stationaryStartTime = GetSecs();
                    if ~isWarningOnScreen
                        DrawFormattedText(win, 'WARN PARTICIPANT: Please return to the center.', 'center', 'center', white);
                        Screen('Flip', win);
                        isWarningOnScreen = true;
                    end
                else
                    if isWarningOnScreen
                        Screen('Flip', win);
                        isWarningOnScreen = false;
                    end
                end
                
                WaitSecs(0.01);
            end
            
            n = idx - 1;
            t = tData(1:n);
            
            headTrace.time = t; headTrace.x = hxData(1:n); headTrace.y = hyData(1:n); headTrace.z = hzData(1:n);
            headTrace.roll = hrollData(1:n); headTrace.pitch = hpitchData(1:n); headTrace.yaw = hyawData(1:n); headTrace.error = herrData(1:n);
            
            torsoTrace.time = t; torsoTrace.x = txData(1:n); torsoTrace.y = tyData(1:n); torsoTrace.z = tzData(1:n);
            torsoTrace.roll = trollData(1:n); torsoTrace.pitch = tpitchData(1:n); torsoTrace.yaw = tyawData(1:n); torsoTrace.error = terrData(1:n);
        end

        % ---------------------------------------------------------
        % EXTRACT PAUSED TRACES FROM BUFFER (NON-BLOCKING PAUSE SYSTEM)
        % ---------------------------------------------------------
        function [headTrace, torsoTrace] = ExtractPausedTraces()
            global PAUSED_MOTION_BUFFER
            
            if isempty(PAUSED_MOTION_BUFFER.frames)
                headTrace = OptiTrackBridge.EmptyTrace();
                torsoTrace = OptiTrackBridge.EmptyTrace();
                return;
            end
            
            n = length(PAUSED_MOTION_BUFFER.frames);
            tData = nan(n, 1);
            hxData = nan(n, 1); hyData = nan(n, 1); hzData = nan(n, 1);
            hrollData = nan(n, 1); hpitchData = nan(n, 1); hyawData = nan(n, 1);
            herrData = nan(n, 1);
            txData = nan(n, 1); tyData = nan(n, 1); tzData = nan(n, 1);
            trollData = nan(n, 1); tpitchData = nan(n, 1); tyawData = nan(n, 1);
            terrData = nan(n, 1);
            
            for i = 1:n
                frame = PAUSED_MOTION_BUFFER.frames{i};
                tData(i) = frame.time;
                hxData(i) = frame.headPos(1); hyData(i) = frame.headPos(2); hzData(i) = frame.headPos(3);
                hrollData(i) = frame.headEuler(1); hpitchData(i) = frame.headEuler(2); hyawData(i) = frame.headEuler(3);
                herrData(i) = frame.headErr;
                txData(i) = frame.torsoPos(1); tyData(i) = frame.torsoPos(2); tzData(i) = frame.torsoPos(3);
                trollData(i) = frame.torsoEuler(1); tpitchData(i) = frame.torsoEuler(2); tyawData(i) = frame.torsoEuler(3);
                terrData(i) = frame.torsoErr;
            end
            
            headTrace.time = tData; headTrace.x = hxData; headTrace.y = hyData; headTrace.z = hzData;
            headTrace.roll = hrollData; headTrace.pitch = hpitchData; headTrace.yaw = hyawData; headTrace.error = herrData;
            
            torsoTrace.time = tData; torsoTrace.x = txData; torsoTrace.y = tyData; torsoTrace.z = tzData;
            torsoTrace.roll = trollData; torsoTrace.pitch = tpitchData; torsoTrace.yaw = tyawData; torsoTrace.error = terrData;
        end

        % ---------------------------------------------------------
        % UNIFIED DATA EXTRACTION HELPER
        % ---------------------------------------------------------
        function [headPos, torsoPos, headEuler, torsoEuler, headErr, torsoErr, frameTimestamp] = GetDualData()
    global OP_BRIDGE_STATE OP_CONTINUOUS_BUFFER PAUSE_ACTIVE PAUSED_MOTION_BUFFER

    headPos = [NaN NaN NaN]; torsoPos = [NaN NaN NaN];      % defaults FIRST
    headEuler = [NaN NaN NaN]; torsoEuler = [NaN NaN NaN];
    headErr = NaN; torsoErr = NaN; frameTimestamp = NaN;

    if ~isstruct(OP_BRIDGE_STATE), return; end               % guard SECOND

    if OP_BRIDGE_STATE.IsDummy                               % IsDummy THIRD
        headPos = [0 0 0]; torsoPos = [0 0 0]; 
        headEuler = [0 0 0]; torsoEuler = [0 0 0]; 
        headErr = 0; torsoErr = 0; frameTimestamp = 0;
        return; 
    end

            
            try
                data = OP_BRIDGE_STATE.NatNetClient.getFrame();
                if isempty(data), data = OP_BRIDGE_STATE.NatNetClient.GetLastFrameOfData(); end
                if isempty(data) || isempty(data.RigidBody), return; end
                
                frameTimestamp = double(data.Timestamp);
                
                % Auto-detect Motive recording start (passive T0 capture)
                if (isprop(data, 'bRecording') || isfield(data, 'bRecording'))
                    if logical(data.bRecording) && OP_BRIDGE_STATE.MotiveT0 == 0
                        OP_BRIDGE_STATE.MotiveT0 = double(data.Timestamp);
                        fprintf('>>> Motive recording detected. T0 = %.6f\n', OP_BRIDGE_STATE.MotiveT0);
                    end
                end
                
                for i = 1:data.RigidBody.Length
    rb = data.RigidBody(i);
    if rb.ID == OptiTrackBridge.HEAD_ID
        headPos = [double(rb.x), double(rb.y), double(rb.z)];
        qx = double(rb.qx); qy = double(rb.qy);
        qz = double(rb.qz); qw = double(rb.qw);
        [r, p, y] = OptiTrackBridge.QuatToEuler(qw, qx, qy, qz);
        headEuler = [r, p, y];
        try
            headErr = double(rb.MeanError);
        catch
            headErr = 0;
        end
    elseif rb.ID == OptiTrackBridge.TORSO_ID
        torsoPos = [double(rb.x), double(rb.y), double(rb.z)];
        qx = double(rb.qx); qy = double(rb.qy);
        qz = double(rb.qz); qw = double(rb.qw);
        [r, p, y] = OptiTrackBridge.QuatToEuler(qw, qx, qy, qz);
        torsoEuler = [r, p, y];
        try
            torsoErr = double(rb.MeanError);
        catch
            torsoErr = 0;
        end
    end
end

                
                % ===== Append to paused motion buffer if pause is active =====

                if PAUSE_ACTIVE
                if ~any(isnan(headPos)) && ~any(isnan(torsoPos))
                    % Ensure frames field exists
                    if ~isfield(PAUSED_MOTION_BUFFER, 'frames')
                        PAUSED_MOTION_BUFFER.frames = {};
                    end
                    
                    frame = struct();
                    frame.rawTimestamp = frameTimestamp;
                    frame.headPos = headPos;
                    frame.torsoPos = torsoPos;
                    frame.headEuler = headEuler;
                    frame.torsoEuler = torsoEuler;
                    frame.headErr = headErr;
                    frame.torsoErr = torsoErr;
                    
                    if OP_BRIDGE_STATE.MotiveT0 > 0
                        frame.time = frameTimestamp - OP_BRIDGE_STATE.MotiveT0;
                    else
                        if isempty(PAUSED_MOTION_BUFFER.frames)
                            frame.time = 0;
                        else
                            frame.time = frameTimestamp - PAUSED_MOTION_BUFFER.frames{1}.rawTimestamp;
                        end
                    end
                    
                    PAUSED_MOTION_BUFFER.frames{end+1} = frame;
                end
            end
                % ==============================================================
                
            catch ME
                disp(['Data Extraction Error: ', ME.message]);
            end
        end

        function [pos, euler, err] = GetPositionAndEuler(rbID)
            global OP_BRIDGE_STATE
            if OP_BRIDGE_STATE.IsDummy
                pos = [0 0 0]; euler = [0 0 0]; err = 0; return; 
            end
            pos = [NaN, NaN, NaN]; euler = [NaN NaN NaN]; err = NaN;
            
            try
                data = OP_BRIDGE_STATE.NatNetClient.getFrame();
                if isempty(data), data = OP_BRIDGE_STATE.NatNetClient.GetLastFrameOfData(); end
                if isempty(data) || isempty(data.RigidBody), return; end
                
                for i = 1:data.RigidBody.Length
                    rb = data.RigidBody(i);
                    if rb.ID == rbID
                        % Position is array [x, y, z]
                        pos = [double(rb.x), double(rb.y), double(rb.z)];
                        qx = double(rb.qx); qy = double(rb.qy);
                        qz = double(rb.qz); qw = double(rb.qw);

                        [r, p, y] = OptiTrackBridge.QuatToEuler(qw, qx, qy, qz);
                        euler = [r, p, y];
                        err = double(rb.MeanError);
                        return;
                    end
                end
            catch
            end
        end

        % --- Backwards Compatibility Wrappers ---
        function [headPos, torsoPos, headEuler, torsoEuler] = GetOpti()
            % Uses the safe, consolidated GetDualData function under the hood
            [headPos, torsoPos, headEuler, torsoEuler, ~, ~] = OptiTrackBridge.GetDualData();
        end

        function pos = GetPosition(rbID)
            [hPos, tPos, ~, ~, ~, ~] = OptiTrackBridge.GetDualData();
            if rbID == OptiTrackBridge.HEAD_ID
                pos = hPos;
            else
                pos = tPos;
            end
        end

        function [headYaw, torsoYaw] = GetDualYaw()
            [~, ~, hEuler, tEuler, ~, ~] = OptiTrackBridge.GetDualData();
            headYaw = hEuler(3);
            torsoYaw = tEuler(3);
        end

        function [headEuler, torsoEuler] = GetDualEuler()
            [~, ~, headEuler, torsoEuler, ~, ~] = OptiTrackBridge.GetDualData();
        end
        
        function [roll, pitch, yaw] = QuatToEuler(qw, qx, qy, qz)
            t0 = 2.0 * (qw * qx + qy * qz);
            t1 = 1.0 - 2.0 * (qx * qx + qy * qy);
            roll = mod(rad2deg(atan2(t0, t1)), 360);

            t2 = max(min(2.0 * (qw * qy - qz * qx), 1.0), -1.0);
            pitch = mod(rad2deg(asin(t2)), 360);
            t3 = 2.0 * (qw * qy - qz * qx);
            t4 = 1.0 - 2.0 * (qy * qy + qz * qz);
            yaw = mod(rad2deg(atan2(t3, t4)), 360);
        end
        
        function yaw = QuatToYaw(qw, qx, qy, qz)
            t3 = 2.0 * (qw * qy - qz * qx);
            t4 = 1.0 - 2.0 * (qy * qy + qz * qz);
            yaw = mod(rad2deg(atan2(t3, t4)), 360);
        end
    end
end
