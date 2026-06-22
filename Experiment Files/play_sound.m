    function play_sound(pa, wav)
        % Plays audio and immediately moves to the next line of code
        PsychPortAudio('FillBuffer', pa, wav);
        PsychPortAudio('Start', pa, 1, 0, 1);
    end
