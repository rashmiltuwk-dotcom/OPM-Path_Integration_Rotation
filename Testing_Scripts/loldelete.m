if ~PAUSE_ACTIVE && kd && any(kc(targetKey))
    % Hold until key is released
    while true
        [kd2, ~, ~] = KbCheck;
        if ~kd2, break; end
        WaitSecs(0.01);
    end
    break;  % Exit recording loop
end
