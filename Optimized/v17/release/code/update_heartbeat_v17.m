function update_heartbeat_v17(caseTag, schemeName, seedVal, ep, numEp)
% UPDATE_HEARTBEAT_V17  Write live execution status to logs/heartbeat_v17.txt
% Overwrites with: timestamp, case, scheme, seed, episode
try
    here = fileparts(mfilename('fullpath'));
    logDir = fullfile(here, 'logs');
    if ~exist(logDir, 'dir'), mkdir(logDir); end
    hbFile = fullfile(logDir, 'heartbeat_v17.txt');
    
    if nargin < 1 || isempty(caseTag), caseTag = 'unknown'; end
    if nargin < 2 || isempty(schemeName), schemeName = 'unknown'; end
    if nargin < 3 || isempty(seedVal), seedVal = 0; end
    if nargin < 4 || isempty(ep), ep = 0; end
    if nargin < 5 || isempty(numEp), numEp = 0; end
    
    ts = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    if ep > 0 && numEp > 0
        epStr = sprintf('%d/%d', ep, numEp);
    elseif ep > 0
        epStr = sprintf('%d', ep);
    else
        epStr = 'N/A';
    end
    
    msg = sprintf('timestamp: %s\ncase: %s\nscheme: %s\nseed: %d\nepisode: %s\n', ...
        ts, char(caseTag), char(schemeName), seedVal, epStr);
        
    for attempt = 1:5
        fid = fopen(hbFile, 'w');
        if fid >= 0
            fwrite(fid, msg);
            fclose(fid);
            break;
        end
        pause(0.05);
    end
catch
    % Non-blocking: never interrupt training if heartbeat fails
end
end
