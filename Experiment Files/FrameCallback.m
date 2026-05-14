function FrameCallback(data)
% FRAMECALLBACK  Called by the natnet listener every time Motive sends a frame.
% This function runs at 120Hz in the background, completely independent of
% the Psychtoolbox rendering loop.
%
% CRITICAL: This file must live in the same folder as OptiTrackBridge.m
% and runExperimentTest.m, or be on the MATLAB path.
%
% INPUT: data — a NatNet FrameOfMocapData struct containing all rigid bodies

global OP_DATA_BUFFER OP_RECORDING OP_BRIDGE_STATE

% Only record when a trial phase is active
if ~OP_RECORDING
    return;
end

try
    % --- GUARD: skip if no rigid body data ---
    if isempty(data) || data.nRigidBodies == 0
        return;
    end
    if data.bIsRecording && OP_BRIDGE_STATE.RecordingStartTime == 0
        OP_BRIDGE_STATE.RecordingStartTime = GetSecs;
        fprintf('>>> Motive Recording Detected. T=0 anchored.\n');
    end

    % --- BUILD THE ROW ---
    % Use OptiTrack's own hardware timestamp for perfect 120Hz spacing.
    % fTimestamp is seconds since Motive started — we normalise to trial
    % start time later when packaging the trace.
    row.time   = double(data.fTimestamp);

    row.hx     = NaN; row.hy = NaN; row.hz = NaN;
    row.hroll  = NaN; row.hpitch = NaN; row.hyaw = NaN;

    row.tx     = NaN; row.ty = NaN; row.tz = NaN;
    row.troll  = NaN; row.tpitch = NaN; row.tyaw = NaN;

    % --- EXTRACT HEAD (ID=1) AND TORSO (ID=2) ---
    for i = 1:data.nRigidBodies
        rb = data.RigidBodies(i);

        % Skip if tracking is lost for this body
        % --- UPDATED GUARD ---
        % 1. rb.MeanError < 0: Body is occluded/missing.
        % 2. rb.MeanError == 0: Solver has failed/frozen (common in some SDK versions).
        % 3. rb.MeanError > 0.04: Geometry is broken (threshold of 4cm).
        if rb.MeanError <= 0 || rb.MeanError > 0.04
            continue; 
        end

        [r, p, y] = QuatToEuler(rb.qw, rb.qx, rb.qy, rb.qz);

        if rb.ID == 1  % HEAD_ID
            row.hx = double(rb.x); row.hy = double(rb.y); row.hz = double(rb.z);
            row.hroll = r; row.hpitch = p; row.hyaw = y;
        elseif rb.ID == 2  % TORSO_ID
            row.tx = double(rb.x); row.ty = double(rb.y); row.tz = double(rb.z);
            row.troll = r; row.tpitch = p; row.tyaw = y;
        end
    end

    % --- APPEND TO BUFFER ---
    % OP_DATA_BUFFER is a pre-allocated struct array.
    % OP_DATA_BUFFER.idx tracks the next write position.
    idx = OP_DATA_BUFFER.idx;
    if idx <= OP_DATA_BUFFER.maxSamples
        OP_DATA_BUFFER.time(idx)   = row.time;
        OP_DATA_BUFFER.hx(idx)     = row.hx;
        OP_DATA_BUFFER.hy(idx)     = row.hy;
        OP_DATA_BUFFER.hz(idx)     = row.hz;
        OP_DATA_BUFFER.hroll(idx)  = row.hroll;
        OP_DATA_BUFFER.hpitch(idx) = row.hpitch;
        OP_DATA_BUFFER.hyaw(idx)   = row.hyaw;
        OP_DATA_BUFFER.tx(idx)     = row.tx;
        OP_DATA_BUFFER.ty(idx)     = row.ty;
        OP_DATA_BUFFER.tz(idx)     = row.tz;
        OP_DATA_BUFFER.troll(idx)  = row.troll;
        OP_DATA_BUFFER.tpitch(idx) = row.tpitch;
        OP_DATA_BUFFER.tyaw(idx)   = row.tyaw;
        OP_DATA_BUFFER.idx         = idx + 1;
    end

catch
    % Silently suppress — never let a callback crash the experiment
end

end


% =========================================================================
% LOCAL HELPER — Quaternion to Euler (duplicated here so the callback file
% is fully self-contained and does not depend on OptiTrackBridge being on
% the path at callback execution time)
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
