function FrameCallback(data)
% FRAMECALLBACK  Called by the natnet listener every time Motive sends a frame.
% This function runs at 120Hz in the background, completely independent of
% the Psychtoolbox rendering loop.
%
% CRITICAL: This file must live in the same folder as OptiTrackBridge.m
% and runExperimentTest.m, or be on the MATLAB path.
%
% INPUT: data — a NatNet FrameOfMocapData struct containing all rigid bodies

global OP_DATA_BUFFER OP_RECORDING OP_BRIDGE_STATE OP_CONTINUOUS_BUFFER 

    if data.bRecording && OP_BRIDGE_STATE.MotiveT0 == 0
        OP_BRIDGE_STATE.MotiveT0 = double(data.fTimestamp);
        fprintf('>>> Motive Recording Detected. T=0 anchored.\n');
    end

% If error occur try bIsRecording instead of bRecording

try
    % --- GUARD: skip if no rigid body data ---
    if isempty(data) || data.nRigidBodies == 0
        return;
    end

    % --- BUILD THE ROW ---
    row.time   = double(data.fTimestamp);

    row.hx     = NaN; row.hy = NaN; row.hz = NaN;
    row.hroll  = NaN; row.hpitch = NaN; row.hyaw = NaN;
    row.hErr   = NaN; % Added error metric

    row.tx     = NaN; row.ty = NaN; row.tz = NaN;
    row.troll  = NaN; row.tpitch = NaN; row.tyaw = NaN;
    row.tErr   = NaN; % Added error metric

    % --- EXTRACT HEAD (ID=1) AND TORSO (ID=2) ---
    for i = 1:data.nRigidBodies
        rb = data.RigidBodies(i);

        [r, p, y] = QuatToEuler(rb.qw, rb.qx, rb.qy, rb.qz);

        if rb.ID == OptiTrackBridge.HEAD_ID
            row.hErr = double(rb.MeanError); % Always record the error state
            
            % Only record positions if tracking is good
            if rb.MeanError > 0 && rb.MeanError <= 0.04
                row.hx = double(rb.x); row.hy = double(rb.y); row.hz = double(rb.z);
                row.hroll = r; row.hpitch = p; row.hyaw = y;
            end
            
        elseif rb.ID == OptiTrackBridge.TORSO_ID
            row.tErr = double(rb.MeanError); % Always record the error state
            
            % Only record positions if tracking is good
            if rb.MeanError > 0 && rb.MeanError <= 0.04
                row.tx = double(rb.x); row.ty = double(rb.y); row.tz = double(rb.z);
                row.troll = r; row.tpitch = p; row.tyaw = y;
            end
        end
    end

    % --- APPEND TO TRIAL BUFFER ---
    % Only writes during active trial recording phases (gated by OP_RECORDING)
    if ~isempty(OP_RECORDING) && OP_RECORDING
        idx = OP_DATA_BUFFER.idx;
        if idx <= OP_DATA_BUFFER.maxSamples
            OP_DATA_BUFFER.time(idx)   = row.time;
            OP_DATA_BUFFER.hx(idx)     = row.hx;
            OP_DATA_BUFFER.hy(idx)     = row.hy;
            OP_DATA_BUFFER.hz(idx)     = row.hz;
            OP_DATA_BUFFER.hroll(idx)  = row.hroll;
            OP_DATA_BUFFER.hpitch(idx) = row.hpitch;
            OP_DATA_BUFFER.hyaw(idx)   = row.hyaw;
            OP_DATA_BUFFER.hErr(idx)   = row.hErr;
            OP_DATA_BUFFER.tx(idx)     = row.tx;
            OP_DATA_BUFFER.ty(idx)     = row.ty;
            OP_DATA_BUFFER.tz(idx)     = row.tz;
            OP_DATA_BUFFER.troll(idx)  = row.troll;
            OP_DATA_BUFFER.tpitch(idx) = row.tpitch;
            OP_DATA_BUFFER.tyaw(idx)   = row.tyaw;
            OP_DATA_BUFFER.tErr(idx)   = row.tErr;
            OP_DATA_BUFFER.idx         = idx + 1;
        end
    end

    % --- APPEND TO CONTINUOUS BUFFER ---
    % No gate — always writes from Connect to Disconnect regardless of
    % trial state, capturing the full session including inter-trial gaps.
    cidx = OP_CONTINUOUS_BUFFER.idx;
    if cidx <= OP_CONTINUOUS_BUFFER.maxSamples
        OP_CONTINUOUS_BUFFER.time(cidx)   = row.time;
        OP_CONTINUOUS_BUFFER.hx(cidx)     = row.hx;
        OP_CONTINUOUS_BUFFER.hy(cidx)     = row.hy;
        OP_CONTINUOUS_BUFFER.hz(cidx)     = row.hz;
        OP_CONTINUOUS_BUFFER.hroll(cidx)  = row.hroll;
        OP_CONTINUOUS_BUFFER.hpitch(cidx) = row.hpitch;
        OP_CONTINUOUS_BUFFER.hyaw(cidx)   = row.hyaw;
        OP_CONTINUOUS_BUFFER.hErr(cidx)   = row.hErr;
        OP_CONTINUOUS_BUFFER.tx(cidx)     = row.tx;
        OP_CONTINUOUS_BUFFER.ty(cidx)     = row.ty;
        OP_CONTINUOUS_BUFFER.tz(cidx)     = row.tz;
        OP_CONTINUOUS_BUFFER.troll(cidx)  = row.troll;
        OP_CONTINUOUS_BUFFER.tpitch(cidx) = row.tpitch;
        OP_CONTINUOUS_BUFFER.tyaw(cidx)   = row.tyaw;
        OP_CONTINUOUS_BUFFER.tErr(cidx)   = row.tErr;
        OP_CONTINUOUS_BUFFER.idx          = cidx + 1;
    end

catch
    % Silently suppress — never let a callback crash the experiment
end

end


% =========================================================================
% LOCAL HELPER 
% =========================================================================
function [roll, pitch, yaw] = QuatToEuler(qw, qx, qy, qz)
    % Roll (X-axis)
    t0 = 2.0 * (qw * qx + qy * qz);
    t1 = 1.0 - 2.0 * (qx * qx + qy * qy);
    roll = rad2deg(atan2(t0, t1));

    % Pitch (Y-axis)
    t2 = max(min(2.0 * (qw * qy - qz * qx), 1.0), -1.0);
    pitch = rad2deg(asin(t2));

    % Yaw (Z-axis) — normalised to 0-360 compass heading
    t3 = 2.0 * (qw * qz + qx * qy);
    t4 = 1.0 - 2.0 * (qy * qy + qz * qz);
    yaw = mod(rad2deg(atan2(t3, t4)), 360);
end
