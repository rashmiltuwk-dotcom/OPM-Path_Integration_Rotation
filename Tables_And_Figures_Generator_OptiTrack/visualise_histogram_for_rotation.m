%% ============================================================
%  GRAND SUMMARY: YAW POLAR HISTOGRAMS (FILTERED OR ALL)
% ============================================================
 
%% --- 1. SETUP PARAMETERS -----------------------------------
% To select "All", use {'All'} in the cell array.
events = {'EncodingRotate', 'ResponseRotation'};
pos    = {'LPos', 'RPos'}; 
dirs   = {'L', 'R'};       
 
degs     = [60, 120, 240, 300];
binEdges = -180:20:180;
 
accepted = MasterData(strcmp({MasterData.Status}, 'Accepted'));
figCount = 1;
 
%% --- 2. FIGURE GENERATION LOOP -----------------------------
% If 'All' is in the lists, expand them to include all actual categories
if any(strcmp(events, 'All')), events = {'EncodingRotate', 'ResponseRotation'}; end
if any(strcmp(pos, 'All')),    pos    = {'LPos', 'RPos'}; end
if any(strcmp(dirs, 'All')),   dirs   = {'L', 'R'}; end
 
for e = 1:length(events)
    for p = 1:length(pos)
        for d = 1:length(dirs)
            
            % Create Figure Window
            figure(figCount); clf;
            set(gcf, 'Position', [100 + (figCount*50), 100, 1000, 800], 'Color', 'w');
            
            figTitle = sprintf('%s | Start: %s | Turn: %s', events{e}, pos{p}, dirs{d});
            if strcmp(events{e}, 'ResponseRotation'), figTitle = [figTitle, ' (Physical Only)']; end
            sgtitle(figTitle, 'FontSize', 18, 'FontWeight', 'bold');
            
            % Create 4 Quadrant Subplots with Polar Axes
            for q = 1:length(degs)
                
                % Create polar axes explicitly
                ax = polaraxes('Parent', gcf, 'Position', get_subplot_position(q));
                hold on;
                
                % 1. Filter Data (Checks for exact match)
                mask = strcmp({accepted.Position}, pos{p}) & ...
                       strcmp({accepted.Direction}, dirs{d}) & ...
                       [accepted.TargetDeg] == degs(q);
                sub = accepted(mask);
                
                if isempty(sub)
                    title(sprintf('Q%d: %d° (N=0)', q, degs(q)), 'FontSize', 14);
                    continue;
                end
                
                % 2. Exclusion Rule
                if strcmp(events{e}, 'ResponseRotation'), sub = sub(~strcmp({sub.TaskType}, 'I')); end
                
                % 3. Extract & Plot
                headYaw  = get_yaw_data(sub, [events{e}, 'HeadTrace']);
                torsoYaw = get_yaw_data(sub, [events{e}, 'TorsoTrace']);
                
                if ~isempty(headYaw)
                    polarhistogram(deg2rad(headYaw), deg2rad(binEdges), 'Normalization', 'count', ...
                        'FaceAlpha', 0.5, 'EdgeColor', 'k', 'LineWidth', 1.5, 'FaceColor', [0 0.8 1]);
                end
                if ~isempty(torsoYaw)
                    polarhistogram(deg2rad(torsoYaw), deg2rad(binEdges), 'Normalization', 'count', ...
                        'FaceAlpha', 0.5, 'EdgeColor', 'k', 'LineWidth', 1.5, 'FaceColor', [1 0 0.3]);
                end
                
                % 4. Format Axes
                ax.ThetaZeroLocation = 'top'; ax.ThetaDir = 'clockwise';
                ax.ThetaTick = 0:30:330; ax.RTickLabels = {}; ax.GridAlpha = 0.3;   
                title(sprintf('Q%d: %d° (N=%d)', q, degs(q), numel(sub)), 'FontSize', 14);
                hold off;
            end
            figCount = figCount + 1;
        end
    end
end
 
%% --- LOCAL HELPER FUNCTION ---------------------------------
function val = resolve_filter(code, map)
    if strcmp(code, 'All'), val = NaN; else, val = map(code); end
end

function pos = get_subplot_position(q)
    % Calculate position for 2x2 subplot grid
    % q: 1 (top-left), 2 (top-right), 3 (bottom-left), 4 (bottom-right)
    row = ceil(q / 2) - 1;
    col = mod(q - 1, 2);
    left   = 0.12 + col * 0.45;
    bottom = 0.55 - row * 0.45;
    width  = 0.35;
    height = 0.35;
    pos = [left, bottom, width, height];
end
 
function yData = get_yaw_data(trials, traceName)
    yData = [];
    for i = 1:numel(trials)
        if isfield(trials(i).Traces, traceName) && ~isempty(trials(i).Traces.(traceName))
            tr = trials(i).Traces.(traceName);
            if isfield(tr, 'yaw'),     yData = [yData; tr.yaw(:)];
            elseif isfield(tr, 'Yaw'), yData = [yData; tr.Yaw(:)];
            end
        end
    end
    yData = yData(~isnan(yData));
end
