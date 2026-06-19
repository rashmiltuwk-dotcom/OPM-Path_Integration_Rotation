% --- Ultra-Fast Volumetric Animator (6DOF GPU Accelerated, Offset Only) ---
figure(2); clf;
% Forcing OpenGL hardware acceleration for max framerate
set(gcf, 'Color', 'w', 'Position', [100, 100, 1000, 800], 'Renderer', 'opengl');

% === TIME CONTROL SETTINGS ===
timeStart = 624;   % Start playback at this time (seconds)
timeEnd   = 750;   % End playback at this time (seconds)
% =============================

% Filter data by time window
timeMask = headTrace.time >= timeStart & headTrace.time <= timeEnd;
validIdx = find(timeMask);
if isempty(validIdx)
    error('No data found. Check your timeStart and timeEnd values.');
end

% Cap index to ensure we don't exceed data bounds
maxValidIndex = min([validIdx(end), length(headTrace.x), length(torsoTrace.x)]);
idx = validIdx(1):1:maxValidIndex;

% Setup Plot
ax = axes('Projection', 'perspective');
hold on; grid on; axis equal; view(3); 
xlabel('Room X (Left-Right)', 'FontSize', 12); 
ylabel('Room Z (Forward-Back)', 'FontSize', 12); 
zlabel('Room Y (Height)', 'FontSize', 12);

% Set axes limits dynamically based on the whole dataset
allX = [headTrace.x; torsoTrace.x];
allY = [headTrace.y; torsoTrace.y];
allZ = [headTrace.z; torsoTrace.z];
xlim([min(allX)-1, max(allX)+1]);
ylim([min(allZ)-1, max(allZ)+1]);     
zlim([min(allY)-0.5, max(allY)+0.5]); 

% --- GEOMETRY & GPU SETUP ---

% Create hardware transform objects 
headTransform = hgtransform('Parent', ax);
torsoTransform = hgtransform('Parent', ax);

% 1. Head Geometry (Parented to headTransform)
headRadius = 0.57 / (2 * pi); 
[sx, sy, sz] = sphere(10); 
baseHeadX = sx * headRadius;
baseHeadY = sy * headRadius;
baseHeadZ = sz * headRadius;

surf(baseHeadX, baseHeadY, baseHeadZ, 'Parent', headTransform, ...
    'FaceColor', [0.2 0.6 1.0], 'EdgeColor', 'none', 'FaceAlpha', 0.9);

% HEAD FORWARD INDICATOR (3D Red Arrow)
% Draws shaft, horizontal barbs, and vertical barbs
hx_arr = [0, 0, NaN, -0.04, 0, 0.04, NaN, 0, 0, 0];
hy_arr = [0, 0.25, NaN, 0.19, 0.25, 0.19, NaN, 0.19, 0.25, 0.19];
hz_arr = [0, 0, NaN, 0, 0, 0, NaN, -0.04, 0, 0.04];
plot3(hx_arr, hy_arr, hz_arr, 'r-', 'LineWidth', 4, 'Parent', headTransform);

% 2. Torso Geometry (Parented to torsoTransform)
tWidth  = 0.30; % 30 cm wide
tDepth  = 0.15; % 15 cm deep
tHeight = 0.40; % 40 cm tall

vX = [-1  1  1 -1 -1  1  1 -1] * (tWidth/2);
vY = [-1 -1  1  1 -1 -1  1  1] * (tDepth/2);
vZ = [-1 -1 -1 -1  1  1  1  1] * (tHeight/2);
faces = [1 2 3 4; 5 6 7 8; 1 2 6 5; 2 3 7 6; 3 4 8 7; 4 1 5 8];
baseTorsoVertices = [vX', vY', vZ'];

patch('Vertices', baseTorsoVertices, 'Faces', faces, 'Parent', torsoTransform, ...
    'FaceColor', [1.0 0.4 0.4], 'EdgeColor', 'k', 'FaceAlpha', 0.8, 'LineWidth', 0.5);

% TORSO FORWARD INDICATOR (3D Green Arrow)
% Draws shaft, horizontal barbs, and vertical barbs
tx_arr = [0, 0, NaN, -0.05, 0, 0.05, NaN, 0, 0, 0];
ty_arr = [0, 0.35, NaN, 0.27, 0.35, 0.27, NaN, 0.27, 0.35, 0.27];
tz_arr = [0, 0, NaN, 0, 0, 0, NaN, -0.05, 0, 0.05];
plot3(tx_arr, ty_arr, tz_arr, 'g-', 'LineWidth', 4, 'Parent', torsoTransform);

% Lighting
camlight; 
lighting gouraud;

% Trailing Lines
headTail = animatedline('Color', [0.2 0.6 1.0 0.5], 'LineWidth', 1.5, 'MaximumNumPoints', 50);
torsoTail = animatedline('Color', [1.0 0.4 0.4 0.5], 'LineWidth', 1.5, 'MaximumNumPoints', 50);

% Initialize an empty title
hTitle = title('', 'FontSize', 14);

% --- High-Speed Animation Loop ---
for i = idx
    % Stop safely if the window is closed
    if ~isvalid(ax)
        disp('Figure closed. Stopping animation.');
        break; 
    end
    
    % Extract Positions
    hx = headTrace.x(i);
    hy = headTrace.y(i);
    hz = headTrace.z(i);
    
    tx = torsoTrace.x(i);
    ty = torsoTrace.y(i);
    tz = torsoTrace.z(i);
    
    % --- OFFSET CALIBRATION ---
    % Subtract 90 degrees to lay the arrows flat on the Y axis
    pitchOffset = 0;  
    yawOffset   = 0;
    rollOffset  = 0;
    
    % Extract Angles, apply offsets, and convert directly to radians
    hYaw   = deg2rad(headTrace.yaw(i) - yawOffset);
    hPitch = deg2rad(headTrace.pitch(i) - pitchOffset);
    hRoll  = deg2rad(headTrace.roll(i) - rollOffset);
    
    tYaw   = deg2rad(torsoTrace.yaw(i) - yawOffset);
    tPitch = deg2rad(torsoTrace.pitch(i) - pitchOffset);
    tRoll  = deg2rad(torsoTrace.roll(i) - rollOffset);
    
    % Update trailing paths (Applying Y-to-Z mapping)
    addpoints(headTail, hx, hz, hy);
    addpoints(torsoTail, tx, tz, ty);
    
    % --- Apply 6DOF GPU Transforms ---
    
    % Build translation matrices (Mapped axes)
    headT  = makehgtform('translate', [hx, hz, hy]);
    torsoT = makehgtform('translate', [tx, tz, ty]);
    
    % Build rotation matrices mapped to visual axes
    headRot  = makehgtform('zrotate', hYaw) * makehgtform('xrotate', hPitch) * makehgtform('yrotate', hRoll);
    torsoRot = makehgtform('zrotate', tYaw) * makehgtform('xrotate', tPitch) * makehgtform('yrotate', tRoll);
    
    % Combine Translation and Rotation
    headTransform.Matrix  = headT * headRot;
    torsoTransform.Matrix = torsoT * torsoRot;
    
    % Update the live timer and frame counter
    hTitle.String = sprintf('OPM-MEG Tracking | Time: %.2f s | Frame: %d', headTrace.time(i), i);
    
    % Force the GPU to render this frame immediately
    drawnow; 
end
