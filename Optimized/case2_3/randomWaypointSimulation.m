function varargout = randomWaypointSimulation(numUsers,simTime)
    % Simulation Parameters
    %numUsers = 5;              % Number of users
    areaSize = 1000;            % Area size (square: areaSize x areaSize)
    %simTime = 100;             % Total simulation time in seconds
    dt = 1;                    % Time step in seconds
        
    pauseTime = 0;             % Pause time at each waypoint (seconds)
    
    % Initialize user state
    users(numUsers) = struct();
    for i = 1:numUsers
        users(i).pos = areaSize * rand(1,2);    % Initial position
        users(i).dest = areaSize * rand(1,2);   % First destination
        users(i).speed = 5;
        users(i).pause = 0;                     % Pause counter
        users(i).trajectory = users(i).pos;     % Store path
    end

    % Simulation loop
    for t = 0:dt:simTime
        clf;
        hold on;
        axis([0 areaSize 0 areaSize]);
        title(sprintf('Random Waypoint Model at t = %.1f sec', t));
        xlabel('X (m)');
        ylabel('Y (m)');
        
        for i = 1:numUsers
            user = users(i);
            if user.pause > 0
                user.pause = user.pause - dt;
            else
                direction = user.dest - user.pos;
                distanceToDest = norm(direction);
                if distanceToDest < user.speed * dt
                    user.pos = user.dest;
                    user.dest = areaSize * rand(1,2);
                    user.speed = 5;
                    user.pause = pauseTime;
                else
                    user.pos = user.pos + (user.speed * dt) * (direction / distanceToDest);
                end
            end
            user.trajectory(end+1, :) = user.pos;
            users(i) = user;

            % Plot user
            plot(user.pos(1), user.pos(2), 'bo', 'MarkerSize', 6, 'MarkerFaceColor', 'b');
            plot(user.trajectory(:,1), user.trajectory(:,2), 'b--');
        end
        
        drawnow;
        pause(0.001);  % for animation
    end
    for i=1:numUsers
        varargout{i}=users(i).trajectory(3:end,:);
    end
end