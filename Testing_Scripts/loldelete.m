infile   = 'C:/Users/spaceandmem/rashmil_opm/data_dump/Imagniation-run-002_30-06-2026_16-59-42_array1.lvm';
nchunks  = 6;

if ~isfile(infile)
    error('File not found: %s', infile);
end

[folder, name, ~] = fileparts(infile);

% --- Pass 1: capture header lines, locate Samples tag, count data rows ---
fid = fopen(infile, 'r');
if fid == -1, error('fopen failed to open: %s', infile); end

headerLines = {};
samplesLineIdx = 0;
endOfHeaderCount = 0;
while true
    line = fgetl(fid);
    headerLines{end+1} = line;
    if startsWith(line, 'Samples')
        samplesLineIdx = numel(headerLines);
    end
    if contains(line, 'End_of_Header')
        endOfHeaderCount = endOfHeaderCount + 1;
        if endOfHeaderCount == 2
            headerLines{end+1} = fgetl(fid); % column heading row
            break
        end
    end
end
if samplesLineIdx == 0
    error('Could not find Samples tag in header - cannot safely split this file.');
end

nDataLines = 0;
while ~feof(fid)
    fgetl(fid);
    nDataLines = nDataLines + 1;
end
fclose(fid);

rowsPerChunk = ceil(nDataLines / nchunks);
samplesParts = strsplit(headerLines{samplesLineIdx}, '\t');
nCols = numel(samplesParts) - 1; % first token is the "Samples" tag itself

% --- Pass 2: stream data rows into nchunks files, correcting Samples tag per part ---
fid = fopen(infile, 'r');
for i = 1:numel(headerLines)
    fgetl(fid);
end

for c = 1:nchunks
    outfile = fullfile(folder, sprintf('%s_part%d.lvm', name, c));
    fout = fopen(outfile, 'w');
    if fout == -1, error('fopen failed to create: %s', outfile); end

    dataBuffer = {};
    for r = 1:rowsPerChunk
        line = fgetl(fid);
        if ~ischar(line), break; end
        dataBuffer{end+1} = line;
    end
    rowsWritten = numel(dataBuffer);

    correctedSamplesLine = sprintf('Samples%s', repmat(sprintf('\t%d', rowsWritten), 1, nCols));

    for h = 1:numel(headerLines)
        if h == samplesLineIdx
            fprintf(fout, '%s\n', correctedSamplesLine);
        else
            fprintf(fout, '%s\n', headerLines{h});
        end
    end
    for r = 1:rowsWritten
        fprintf(fout, '%s\n', dataBuffer{r});
    end
    fclose(fout);
end
fclose(fid);

clear infile nchunks folder name fid headerLines samplesLineIdx endOfHeaderCount ...
      line nDataLines rowsPerChunk samplesParts nCols i c outfile fout dataBuffer ...
      r rowsWritten correctedSamplesLine h
