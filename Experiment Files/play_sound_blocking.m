    function play_sound_blocking(pa, wav)
        % Plays audio and pauses MATLAB until the audio finishes playing
        PsychPortAudio('FillBuffer', pa, wav);
        PsychPortAudio('Start', pa, 1, 0, 1); 
        PsychPortAudio('Stop', pa, 1);        
    end
