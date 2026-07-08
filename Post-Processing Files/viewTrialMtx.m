clear conditionlabels conditions
nTrials  = ntrials(epoch_D);
nSamps   = nsamples(epoch_D);
fsHz     = fsample(epoch_D);
epochDur = nSamps / fsHz;              % duration of every epoch, in seconds
condlabels_all = conditions(epoch_D);

rows = struct('Trial', {}, 'Label', {}, 'Status', {}, 'TrialNum', {}, ...
              'TaskType', {}, 'Direction', {}, 'Quadrant', {}, 'Distance', {}, ...
              'Onset_s', {}, 'Duration_s', {}, 'Offset_s', {});

for t = 1:nTrials
    ev = events(epoch_D, t);
    if iscell(ev), ev = ev{1}; end

    row.Trial    = t;
    row.Label    = condlabels_all{t};
    row.Status   = '';                       % blank for PAUSED — no status event exists for those
    row.Onset_s  = trialonset(epoch_D, t);    % t_zero-relative, from the fix we applied
    row.Duration_s = epochDur;
    row.Offset_s = row.Onset_s + epochDur;

    for e = 1:numel(ev)
        switch ev(e).type
            case {'ACCEPTED','REJECTED'}
                row.Status = ev(e).type;
            otherwise
                row.(ev(e).type) = ev(e).value;
        end
    end

    rows(end+1) = row; %#ok<AGROW>
end

trialMatrix = struct2table(rows)
