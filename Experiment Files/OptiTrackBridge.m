classdef OptiTrackBridge
    % OPTITRACKBRIDGE
    % Handles connection to OptiTrack Motive using the natnet class.
    % Uses event callbacks (120Hz) instead of polling to capture data.
    % FrameCallback.m must be in the same folder or on the MATLAB path.

    properties (Constant)
        FORCE_DUMMY_MODE = false;

        % --- NETWORKING ---
        HOST_IP   = '128.40.164.130';
        CLIENT_IP = '128.40.164.174';

        % --- RIGID BODY IDs (must match Motive) ---
        HEAD_ID  = 1;
        TORSO_ID = 2;

        % --- BUFFER SIZE ---
        % 120Hz 
        MAX_SAMPLES = 10000;
    end

    properties (GetAccess = private, SetAccess = private)
        NatNetClient
        IsConnected = false;
        IsDummy     = false;
        LogFileID   = -1;
    end

    properties (GetAccess = public, SetAccess = public)
        RecordingStartTime = 0; 
    end

    methods (Static)

        % =================================================================
        % CONNECT
        % =================================================================
        function success = Connect(subjectID)
            global OP_BRIDGE_STATE OP_DATA_BUFFER OP_RECORDING

            clear global OP_BRIDGE_STATE;
            global OP_BRIDGE_STATE

            OP_BRIDGE_STATE = OptiTrackBridge;
            OP_RECORDING    = false;

            % --- Initialize Event CSV ---
            logName = sprintf('Motive_Events_Subj%s_%s.csv', subjectID, datestr(now, 'yyyymmdd_HHMM'));
            OP_BRIDGE_STATE.LogFileID = fopen(logName, 'a');
            fprintf(OP_BRIDGE_STATE.LogFileID, 'RecordingTime,TrialNum,EventName,State\n');

            % --- Pre-allocate the buffer with NaN arrays ---
            % Writing into a pre-allocated array is near-instant.
            % This avoids MATLAB reallocating memory at 120Hz.
            n = OptiTrackBridge.MAX_SAMPLES;
            OP_DATA_BUFFER.idx     = 1;         % next write position
            OP_DATA_BUFFER.maxSamples = n;
            OP_DATA_BUFFER.time    = NaN(n, 1);
            OP_DATA_BUFFER.hx      = NaN(n, 1);
            OP_DATA_BUFFER.hy      = NaN(n, 1);
            OP_DATA_BUFFER.hz      = NaN(n, 1);
            OP_DATA_BUFFER.hroll   = NaN(n, 1);
            OP_DATA_BUFFER.hpitch  = NaN(n, 1);
            OP_DATA_BUFFER.hyaw    = NaN(n, 1);
            OP_DATA_BUFFER.hErr    = NaN(n, 1);
            OP_DATA_BUFFER.tx      = NaN(n, 1);
            OP_DATA_BUFFER.ty      = NaN(n, 1);
            OP_DATA_BUFFER.tz      = NaN(n, 1);
            OP_DATA_BUFFER.troll   = NaN(n, 1);
            OP_DATA_BUFFER.tpitch  = NaN(n, 1);
            OP_DATA_BUFFER.tyaw    = NaN(n, 1);
            OP_DATA_BUFFER.tErr    = NaN(n, 1);

            if OptiTrackBridge.FORCE_DUMMY_MODE
                OP_BRIDGE_STATE.IsDummy = true;
                success = true;
                return;
            end

            try
                fprintf('Creating natnet class object...\n');
                OP_BRIDGE_STATE.NatNetClient = natnet;

                fprintf('Connecting to server at %s...\n', OptiTrackBridge.HOST_IP);
                OP_BRIDGE_STATE.NatNetClient.HostIP         = OptiTrackBridge.HOST_IP;
                OP_BRIDGE_STATE.NatNetClient.ClientIP       = OptiTrackBridge.CLIENT_IP;
                OP_BRIDGE_STATE.NatNetClient.ConnectionType = 'Multicast';

                OP_BRIDGE_STATE.NatNetClient.connect;

                if OP_BRIDGE_STATE.NatNetClient.IsConnected == 0
                    warning('Client failed to connect. Falling back to Dummy Mode.');
                    OP_BRIDGE_STATE.IsDummy = true;
                    success = false;
                    return;
                end

                OP_BRIDGE_STATE.IsConnected = true;
                fprintf('Connected to Motive successfully.\n');

                % --- Wire up the 120Hz callback ---
                % Slot 1 → FrameCallback.m (must be on MATLAB path)
                % Listener is OFF by default — StartRecording() enables it.
                OP_BRIDGE_STATE.NatNetClient.addlistener(1, 'FrameCallback');
                fprintf('FrameCallback listener registered (disabled until StartRecording).\n');

                success = true;

            catch ME
                warning('Connection failed: %s. Falling back to Dummy Mode.', ME.message);
                OP_BRIDGE_STATE.IsDummy = true;
                success = false;
            end
        end

        % =================================================================
        % DISCONNECT
        % =================================================================
        function Disconnect()
            global OP_BRIDGE_STATE OP_DATA_BUFFER OP_RECORDING

            if ~isempty(OP_BRIDGE_STATE)
                
                % --- Safely close the CSV file ---
                if OP_BRIDGE_STATE.LogFileID ~= -1
                    fclose(OP_BRIDGE_STATE.LogFileID);
                    OP_BRIDGE_STATE.LogFileID = -1;
                end

                if ~OP_BRIDGE_STATE.IsDummy
                    try
                        % Disable all listeners before disconnecting
                        OP_BRIDGE_STATE.NatNetClient.disable(0);
                        OP_BRIDGE_STATE.NatNetClient.disconnect;
                    catch
                    end
                end
            end

            OP_RECORDING = false;
            clear global OP_BRIDGE_STATE OP_DATA_BUFFER OP_RECORDING;
        end

        % =================================================================
        % EVENT LOGGING
        % =================================================================
        function startEvent(trialNum, eventName)
            global OP_BRIDGE_STATE
            if isempty(OP_BRIDGE_STATE) || OP_BRIDGE_STATE.LogFileID == -1, return; end
            
            if OP_BRIDGE_STATE.RecordingStartTime > 0
                t = GetSecs - OP_BRIDGE_STATE.RecordingStartTime;
            else
                t = 0; % Safety fallback if Motive hasn't started
            end
            fprintf(OP_BRIDGE_STATE.LogFileID, '%.4f,%d,%s,START\n', t, trialNum, eventName);
        end

        function stopEvent(trialNum, eventName)
            global OP_BRIDGE_STATE
            if isempty(OP_BRIDGE_STATE) || OP_BRIDGE_STATE.LogFileID == -1, return; end
            
            if OP_BRIDGE_STATE.RecordingStartTime > 0
                t = GetSecs - OP_BRIDGE_STATE.RecordingStartTime;
            else
                t = 0;
            end
            fprintf(OP_BRIDGE_STATE.LogFileID, '%.4f,%d,%s,STOP\n', t, trialNum, eventName);
        end

        % =================================================================
        % START RECORDING
        % =================================================================
        function StartRecording()
            global OP_BRIDGE_STATE OP_DATA_BUFFER OP_RECORDING

            OP_DATA_BUFFER.idx = 1;

            % --- Tell the system to wait for Motive's flag ---
            OP_BRIDGE_STATE.RecordingStartTime = 0; 

            if OP_BRIDGE_STATE.IsDummy
                OP_RECORDING = true;
                OP_BRIDGE_STATE.RecordingStartTime = GetSecs; % Dummy starts instantly
                return;
            end

            OP_RECORDING = true;
            OP_BRIDGE_STATE.NatNetClient.enable(1);  % enable slot 1
        end

        % =================================================================
        % STOP RECORDING
        % Disables the callback and returns the captured trace structs.
        % headTrace and torsoTrace each have fields:
        %   time, x, y, z, roll, pitch, yaw
        % Time is normalised to start at 0.
        % =================================================================
        function [headTrace, torsoTrace] = StopRecording()
            global OP_BRIDGE_STATE OP_DATA_BUFFER OP_RECORDING

            OP_RECORDING = false;

            if ~OP_BRIDGE_STATE.IsDummy
                OP_BRIDGE_STATE.NatNetClient.disable(1);  % disable slot 1
            end

            % --- Extract valid samples only ---
            n = OP_DATA_BUFFER.idx - 1;  % number of frames actually written

            if n < 1
                % Nothing was recorded — return empty traces
                headTrace  = OptiTrackBridge.EmptyTrace();
                torsoTrace = OptiTrackBridge.EmptyTrace();
                return;
            end

            t = OP_DATA_BUFFER.time(1:n);

            % Normalise time so trace always starts at 0
            t = t - t(1);

            headTrace.time  = t;
            headTrace.x     = OP_DATA_BUFFER.hx(1:n);
            headTrace.y     = OP_DATA_BUFFER.hy(1:n);
            headTrace.z     = OP_DATA_BUFFER.hz(1:n);
            headTrace.roll  = OP_DATA_BUFFER.hroll(1:n);
            headTrace.pitch = OP_DATA_BUFFER.hpitch(1:n);
            headTrace.yaw   = OP_DATA_BUFFER.hyaw(1:n);
            headTrace.error = OP_DATA_BUFFER.hErr(1:n);

            torsoTrace.time  = t;
            torsoTrace.x     = OP_DATA_BUFFER.tx(1:n);
            torsoTrace.y     = OP_DATA_BUFFER.ty(1:n);
            torsoTrace.z     = OP_DATA_BUFFER.tz(1:n);
            torsoTrace.roll  = OP_DATA_BUFFER.troll(1:n);
            torsoTrace.pitch = OP_DATA_BUFFER.tpitch(1:n);
            torsoTrace.yaw   = OP_DATA_BUFFER.tyaw(1:n);
            torsoTrace.error = OP_DATA_BUFFER.tErr(1:n);
            
        end

        % =================================================================
        % GET LATEST FRAME
        % Returns the most recent head and torso data from the buffer.
        % Used by tracking loops for screen feedback — NOT for recording.
        % =================================================================
        function [headPos, torsoPos, headEuler, torsoEuler] = GetOpti()
            global OP_BRIDGE_STATE OP_DATA_BUFFER

            if OP_BRIDGE_STATE.IsDummy
                headPos   = [0 0 0]; torsoPos   = [0 0 0];
                headEuler = [0 0 0]; torsoEuler = [0 0 0];
                return;
            end

            headPos   = [NaN NaN NaN]; torsoPos   = [NaN NaN NaN];
            headEuler = [NaN NaN NaN]; torsoEuler = [NaN NaN NaN];

            idx = OP_DATA_BUFFER.idx - 1;
            if idx < 1, return; end

            % We assume hErr and tErr are now fields in your buffer
            hErr = OP_DATA_BUFFER.hErr(idx);
            tErr = OP_DATA_BUFFER.tErr(idx);

            % If the solver error is exactly 0 (frozen) or > 0.04 (broken)
            % we force the output to NaN so the experiment flags it.
            if hErr <= 0 || hErr > 0.04
                headPos = [NaN NaN NaN]; headEuler = [NaN NaN NaN];
            else
                headPos = [OP_DATA_BUFFER.hx(idx), OP_DATA_BUFFER.hy(idx), OP_DATA_BUFFER.hz(idx)];
                headEuler = [OP_DATA_BUFFER.hroll(idx), OP_DATA_BUFFER.hpitch(idx), OP_DATA_BUFFER.hyaw(idx)];
            end

            if tErr <= 0 || tErr > 0.04
                torsoPos = [NaN NaN NaN]; torsoEuler = [NaN NaN NaN];
            else
                torsoPos = [OP_DATA_BUFFER.tx(idx), OP_DATA_BUFFER.ty(idx), OP_DATA_BUFFER.tz(idx)];
                torsoEuler = [OP_DATA_BUFFER.troll(idx), OP_DATA_BUFFER.tpitch(idx), OP_DATA_BUFFER.tyaw(idx)];
            end
        end

        % =================================================================
        % EMPTY TRACE — returns a zeroed trace struct (dummy / error case)
        % =================================================================
        function trace = EmptyTrace()
            trace.time  = 0; trace.x = 0; trace.y = 0; trace.z = 0;
            trace.roll  = 0; trace.pitch = 0; trace.yaw = 0;
        end

        % =================================================================
        % WAIT FOR ORIGIN (WALKING)
        % =================================================================
        function [distWalkedTorso, distWalkedHead, headTrace, torsoTrace] = WaitForWalkEnd(headID, torsoID, win, tolerance)
            global OP_BRIDGE_STATE

            if nargin < 4, tolerance = 0.10; end

            % --- DUMMY MODE ---
            if OP_BRIDGE_STATE.IsDummy
                DrawFormattedText(win, 'DUMMY MODE: Press "x" to simulate walking.', 'center', 'center', [255 255 0]);
                Screen('Flip', win);
                while true
                    [kd, ~, kc] = KbCheck;
                    if kd && kc(KbName('ESCAPE')), error('User Quit'); end
                    if kd && kc(KbName('r')),      error('Redo_Trial'); end
                    if kd && kc(KbName('x')), WaitSecs(0.3); break; end
                end
                distWalkedTorso = 2.0; distWalkedHead = 2.0;
                headTrace  = OptiTrackBridge.EmptyTrace();
                torsoTrace = OptiTrackBridge.EmptyTrace();
                return;
            end

            white = WhiteIndex(win);
            Screen('TextSize', win, 40);

            % Grab start positions from buffer before recording begins
            [startHeadPos, startTorsoPos, ~, ~] = OptiTrackBridge.GetOpti();

            % --- START 120Hz RECORDING ---
            OptiTrackBridge.StartRecording();

            RENDER_INTERVAL = 0.033;   % ~30Hz screen updates — enough for feedback
            lastRenderTime  = GetSecs();
            currTorsoPos    = startTorsoPos;
            zTarget         = -0.25;

            while true
                [kd, ~, kc] = KbCheck;
                if kd && kc(KbName('ESCAPE')), error('User Quit'); end
                if kd && kc(KbName('r')),      error('Redo_Trial'); end

                % Read latest frame from buffer (never blocks)
                [~, currTorsoPos, ~, ~] = OptiTrackBridge.GetOpti();

                if any(isnan(currTorsoPos))
                    % Only re-render if due — don't block data collection
                    if (GetSecs() - lastRenderTime) >= RENDER_INTERVAL
                        DrawFormattedText(win, '!!! TRACKING LOST !!!\nAdjust markers', 'center', 'center', [255 0 0]);
                        Screen('Flip', win);
                        lastRenderTime = GetSecs();
                    end
                    continue;
                end

                distToCenter = sqrt(currTorsoPos(1)^2 + (currTorsoPos(3) - zTarget)^2);
                inSemiCircle = (distToCenter < tolerance) && (currTorsoPos(3) >= zTarget);

                % --- RENDER at 30Hz only ---
                if (GetSecs() - lastRenderTime) >= RENDER_INTERVAL
                    msg = sprintf('Walk to Start\nDistance: %.2fm', distToCenter);
                    DrawFormattedText(win, msg, 'center', 'center', white);
                    color = [255 0 0];
                    if inSemiCircle, color = [0 255 0]; end
                    centeredRect = CenterRectOnPointd([0 0 50 50], 960, 600);
                    Screen('FillArc', win, color, centeredRect + [0 100 0 100], 270, 180);
                    Screen('Flip', win);
                    lastRenderTime = GetSecs();
                end

                if inSemiCircle
                    DrawFormattedText(win, 'Hold Position...', 'center', 'center', [0 255 0]);
                    Screen('Flip', win);
                    break;
                end
            end

            % --- STOP RECORDING & PACKAGE ---
            [headTrace, torsoTrace] = OptiTrackBridge.StopRecording();

            [~, currHeadPos, ~, ~] = OptiTrackBridge.GetOpti();
            distWalkedTorso = sqrt((currTorsoPos(1) - startTorsoPos(1))^2 + (currTorsoPos(3) - startTorsoPos(3))^2);
            distWalkedHead  = sqrt((currHeadPos(1)  - startHeadPos(1))^2  + (currHeadPos(3)  - startHeadPos(3))^2);
        end

        % =================================================================
        % WAIT FOR ROTATION DUAL (ENCODING TURN)
        % =================================================================
        function [startHead, startTorso, finalHead, finalTorso, headTrace, torsoTrace] = WaitForRotationDual(headID, torsoID, targetDeg, win, dirCode)
            global OP_BRIDGE_STATE

            % --- DUMMY MODE ---
            if OP_BRIDGE_STATE.IsDummy
                DrawFormattedText(win, 'DUMMY MODE: Press "x" to simulate turning.', 'center', 'center', [255 255 0]);
                Screen('Flip', win);
                while true
                    [kd, ~, kc] = KbCheck;
                    if kd && kc(KbName('ESCAPE')), error('User Quit'); end
                    if kd && kc(KbName('r')),      error('Redo_Trial'); end
                    if kd && kc(KbName('x')), WaitSecs(0.3); break; end
                end
                startHead = 0; startTorso = 0; finalHead = targetDeg; finalTorso = targetDeg;
                headTrace  = OptiTrackBridge.EmptyTrace();
                torsoTrace = OptiTrackBridge.EmptyTrace();
                return;
            end

            white = WhiteIndex(win);

            % Capture start yaws before recording
            [~, ~, startHeadEuler, startTorsoEuler] = OptiTrackBridge.GetOpti();
            startHead  = startHeadEuler(3);
            startTorso = startTorsoEuler(3);

            prevTorsoYaw     = startTorso;
            accumulatedTurn  = 0;

            RENDER_INTERVAL = 0.033;
            lastRenderTime  = GetSecs();

            KbReleaseWait;

            % --- START 120Hz RECORDING ---
            OptiTrackBridge.StartRecording();

            while true
                [kd, ~, kc] = KbCheck;
                if kd && kc(KbName('ESCAPE')), error('User Quit'); end
                if kd && kc(KbName('r')),      error('Redo_Trial'); end

                [~, ~, ~, currTorsoEuler] = OptiTrackBridge.GetOpti();

                if any(isnan(currTorsoEuler))
                    if (GetSecs() - lastRenderTime) >= RENDER_INTERVAL
                        DrawFormattedText(win, '!!! TRACKING LOST !!!', 'center', 'center', [255 0 0]);
                        Screen('Flip', win);
                        lastRenderTime = GetSecs();
                    end
                    continue;
                end

                currTorsoYaw = currTorsoEuler(3);

                % Accumulate turn with wrap-around correction
                delta = currTorsoYaw - prevTorsoYaw;
                if delta >  180, delta = delta - 360; end
                if delta < -180, delta = delta + 360; end
                accumulatedTurn = accumulatedTurn + delta;
                prevTorsoYaw    = currTorsoYaw;

                % --- RENDER at 30Hz only ---
                if (GetSecs() - lastRenderTime) >= RENDER_INTERVAL
                    remaining = max(0, targetDeg - abs(accumulatedTurn));
                    msg = sprintf('Turn Body: %.1f / %.1f\nRemaining: %.1f', abs(accumulatedTurn), targetDeg, remaining);
                    DrawFormattedText(win, msg, 'center', 'center', white);
                    Screen('Flip', win);
                    lastRenderTime = GetSecs();
                end

                % --- EXIT CONDITION ---
                if abs(accumulatedTurn) >= targetDeg
                    turnedLeftCorrectly  = strcmpi(dirCode, 'L') && (accumulatedTurn >= targetDeg);
                    turnedRightCorrectly = strcmpi(dirCode, 'R') && (accumulatedTurn <= -targetDeg);

                    if turnedLeftCorrectly || turnedRightCorrectly
                        DrawFormattedText(win, 'DONE! STOP.', 'center', 'center', [0 255 0]);
                        Screen('Flip', win);
                        break;
                    else
                        [headTrace, torsoTrace] = OptiTrackBridge.StopRecording();
                        DrawFormattedText(win, 'INCORRECT DIRECTION\nRestarting...', 'center', 'center', [255 0 0]);
                        Screen('Flip', win);
                        WaitSecs(3.0);
                        error('Redo_Trial');
                    end
                end
            end

            % --- STOP RECORDING & PACKAGE ---
            [headTrace, torsoTrace] = OptiTrackBridge.StopRecording();

            [~, ~, finalHeadEuler, finalTorsoEuler] = OptiTrackBridge.GetOpti();
            finalHead  = finalHeadEuler(3);
            finalTorso = finalTorsoEuler(3);
        end

        % =================================================================
        % RECORD UNTIL KEY (PRODUCTION / IMAGINE WALK)
        % =================================================================
        function [finalHead, finalTorso, headTrace, torsoTrace] = RecordUntilKey(headID, torsoID, keyName, win)
            global OP_BRIDGE_STATE

            targetKey = KbName(keyName);
            escKey    = KbName('ESCAPE');
            xKey      = KbName('x');
            rKey      = KbName('r');

            % --- DUMMY MODE ---
            if OP_BRIDGE_STATE.IsDummy
                DrawFormattedText(win, sprintf('DUMMY MODE: Press "x" or %s to finish.', keyName), 'center', 'center', [255 255 0]);
                Screen('Flip', win);
                while true
                    [kd, ~, kc] = KbCheck;
                    if kd && any(kc(escKey)), error('User Quit'); end
                    if kd && any(kc(rKey)),   error('Redo_Trial'); end
                    if kd && (any(kc(targetKey)) || any(kc(xKey))), WaitSecs(0.3); break; end
                end
                finalHead = 0; finalTorso = 0;
                headTrace  = OptiTrackBridge.EmptyTrace();
                torsoTrace = OptiTrackBridge.EmptyTrace();
                return;
            end

            white = WhiteIndex(win);
            DrawFormattedText(win, sprintf('Perform task...\nPress %s when finished.', keyName), 'center', 'center', white);
            Screen('Flip', win);

            KbReleaseWait;

            % --- START 120Hz RECORDING ---
            OptiTrackBridge.StartRecording();

            while true
                [kd, ~, kc] = KbCheck;
                if kd && any(kc(escKey)),    error('User Quit'); end
                if kd && any(kc(rKey)),      error('Redo_Trial'); end
                if kd && any(kc(targetKey)), break; end
                % No Sleep, no Flip — pure polling of keyboard only.
                % The callback is capturing data at 120Hz in the background.
            end

            % --- STOP RECORDING & PACKAGE ---
            [headTrace, torsoTrace] = OptiTrackBridge.StopRecording();

            [~, ~, finalHeadEuler, finalTorsoEuler] = OptiTrackBridge.GetOpti();
            finalHead  = finalHeadEuler(3);
            finalTorso = finalTorsoEuler(3);
        end

        % =================================================================
        % PASSIVE TRACK (silent post-movement catch)
        % =================================================================
        function [headTrace, torsoTrace] = PassiveTrack(headID, torsoID, durationSecs)
            global OP_BRIDGE_STATE

            if OP_BRIDGE_STATE.IsDummy
                WaitSecs(durationSecs);
                headTrace  = OptiTrackBridge.EmptyTrace();
                torsoTrace = OptiTrackBridge.EmptyTrace();
                return;
            end

            OptiTrackBridge.StartRecording();

            deadline = GetSecs() + durationSecs;
            while GetSecs() < deadline
                [kd, ~, kc] = KbCheck;
                if kd && kc(KbName('ESCAPE')), error('User Quit'); end
                % No Sleep — let the callback fill the buffer unimpeded.
            end

            [headTrace, torsoTrace] = OptiTrackBridge.StopRecording();
        end


        % =================================================================
        % QUATERNION TO EULER  (kept for any external callers)
        % =================================================================
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

    end % methods
end % classdef
