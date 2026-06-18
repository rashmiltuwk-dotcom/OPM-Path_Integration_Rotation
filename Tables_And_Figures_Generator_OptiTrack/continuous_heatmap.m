%% PATH HEATMAP VISUALIZER
timeStart = 0;
timeEnd   = 600; % seconds

figure(1); clf;
set(gcf, 'Position', [100, 100, 1200, 800], 'Color', 'w');

% Filter data by time range
headMask = headTrace.time >= timeStart & headTrace.time <= timeEnd;
torsoMask = torsoTrace.time >= timeStart & torsoTrace.time <= timeEnd;

% Extract coordinates
headX = headTrace.x(headMask);
headZ = headTrace.z(headMask);
torsoX = torsoTrace.x(torsoMask);
torsoZ = torsoTrace.z(torsoMask);

% Determine common axis limits
xLim = [min([headX; torsoX])-1, max([headX; torsoX])+1];
zLim = [min([headZ; torsoZ])-1, max([headZ; torsoZ])+1];

% Create 2D histograms
nBins = 30; %  resolution
[headHist, xEdges, zEdges] = histcounts2(headX, headZ, nBins, 'XBinLimits', xLim, 'YBinLimits', zLim);
[torsoHist, ~, ~] = histcounts2(torsoX, torsoZ, nBins, 'XBinLimits', xLim, 'YBinLimits', zLim);

% Plot head heatmap
subplot(1, 2, 1);
imagesc(xEdges(1:end-1), zEdges(1:end-1), headHist', 'AlphaData', headHist' > 0);
axis image; colorbar; colormap(gca, 'hot');
hold on; plot(0, 0, 'c*', 'MarkerSize', 15, 'LineWidth', 2);
title(sprintf('Head Position Density (t = %.1f - %.1f s)', timeStart, timeEnd), 'FontSize', 14);
xlabel('Room X Position (Meters)', 'FontSize', 12);
ylabel('Room Z Position (Meters)', 'FontSize', 12);
set(gca, 'YDir', 'normal');

% Plot torso heatmap
subplot(1, 2, 2);
imagesc(xEdges(1:end-1), zEdges(1:end-1), torsoHist', 'AlphaData', torsoHist' > 0);
axis image; colorbar; colormap(gca, 'cool');
hold on; plot(0, 0, 'y*', 'MarkerSize', 15, 'LineWidth', 2);
title(sprintf('Torso Position Density (t = %.1f - %.1f s)', timeStart, timeEnd), 'FontSize', 14);
xlabel('Room X Position (Meters)', 'FontSize', 12);
ylabel('Room Z Position (Meters)', 'FontSize', 12);
set(gca, 'YDir', 'normal');

sgtitle('Movement Density Heatmaps', 'FontSize', 16);
