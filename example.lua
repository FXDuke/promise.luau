

local promise = require(game:GetService("ReplicatedStorage"):WaitForChild("Assets"):WaitForChild("SharedScripts"):WaitForChild("promise"));

local function moveBalls(self)
	
	if (workspace.balls.Position.Y > 50) then return self:Reject("Balls is too high") end;
	workspace.balls.Position += Vector3.new(0,100,0);
	self:Resolve("Moved balls");
	
end

local catch = function(promise, errorMsg)
	print("Error:\t"..errorMsg);
	promise:ScheduleAttempt(moveBalls, 1);
end

local reject = function(promise, reason)
	
	print("Rejected:\t"..reason);
	promise:ScheduleAttempt(moveBalls, 1);
	
end

local resolve = function(promise, reason)

	print(promise, reason);
	print("Fulfilled:\t"..reason);
	promise:ScheduleAttempt(moveBalls, 1);

end

local test = promise.new(moveBalls);
test:Then(resolve, reject);
test:Catch(catch);
test:Finally(function()
	print("Promise Settled.");
end)
