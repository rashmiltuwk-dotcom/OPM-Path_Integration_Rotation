%% Plot Digital Triggers (Aligned and Cleaned)
figure()
channels = [5, 8, 6, 9, 2, 10, 7, 3];
labels = {'Close Eyes', 'Stationary', 'Physical Walk', ...
          'Encoding Rot', 'Response Rot', 'Imagine Walk', 'Open Eyes', 'Master Sync'};
colors = lines(length(channels));

% 1. Detect t_zero for time alignment
thresh = 0.05;
chan_idx_all = indchannel(D1, {'T5', 'T8', 'T6', 'T9', 'T2', 'T10', 'T7', 'T3'});
trig_data_all = D1(chan_idx_all, :, 1);
all_channels_high = all(trig_data_all > thresh, 1);
rising_edges = find(diff(all_channels_high) == 1) + 1;

if ~isempty(rising_edges)
    t_zero_sec = rising_edges(1) / D1.fsample;
else
    t_zero_sec = 0;
end

% 2. Create a mask to hide the sync artifacts
% Widening the pulse slightly ensures the edges are fully masked out
sync_mask = conv(double(all_channels_high), ones(1, 20), 'same') > 0;

for k = 1:length(channels)
    i = channels(k);
    label = "T" + i;
    subplot(length(channels), 1, k)
    
    signal = D1(indchannel(D1, label),:,1);
    
    % Blank out the sync pulses on the task channels only
    if k < 8
        signal(sync_mask) = 0; 
    end
    
    % Shift the time axis
    realigned_time = D1.time - t_zero_sec;
    plot(realigned_time, signal, 'Color', colors(k,:))
    title(labels{k})
    
    % Hide the dead time before the experiment started
    xlim([0, max(realigned_time)])
    
    if k < length(channels)
        set(gca, 'XTickLabel', []) 
    else
        xlabel('Time (s)')
    end
end
