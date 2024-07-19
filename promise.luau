-- Typedef

type Promise = {
	status: string,
	Then: ((...any?) -> nil, (...any?) -> nil) -> nil,
	Finally: (...any?) -> nil,
	Catch: (...any?) -> nil,
	Reject: (...any?) -> nil,
	Resolve: (...any?) -> nil,
	Yield: (number) -> nil,
	Close: () -> nil,
	Attempt: ((...any?) -> ...any?, ...any?) -> nil,
	ScheduleAttempt: ((...any?) -> ...any?, number, ...any?) -> nil,
	Clear: () -> nil,
};


-- HIGH ORDER FUNCTIONS

-- Inserts a callback into a promise callback table
local function insertCallback(self, type, callback: (...any?) -> nil)
	table.insert(self.callbacks, {type=type, callback = callback});
end

-- Executes a promise 
local function asynchronousSafeExecutor(promise: Promise, ...)
	
	local routine = promise.routine;
		
	while (true) do
		
		promise.yieldTime = math.max(promise.yieldTime-task.wait(), 0);
		-- Delay execution by time
		if (promise.yieldTime > 0) then continue end;
		
		local success, result = coroutine.resume(routine, promise, ...);

		if (promise.status ~= "pending") then 
			-- If the promise has been resolved in the coroutine
			break;
		end
		
		if (success == false) then
			-- If the coroutine fails it is handled as a reject promise case
			
			promise.status = "rejected";
			
			for _, v in pairs(promise.callbacks) do
				
				if (v.type ~= "catch") then continue end;
				
				task.spawn(v.callback, promise, result);
				
			end
			
			if (promise.status == "rejected") then
				promise:Clear();
			end
			
			break;
		end
		
		if (coroutine.status(routine) ~= "dead") then continue end;
		-- Continue the loop until a result has been returned
		
		if (success) then 
			-- If a result has been returned
			promise:Resolve(result);
			break;
		end
		
	end
	
end

-- PROMISE

local promise;
promise = {
	all = function(promises: {Promise}): Promise -- Array of all resolution values

		local resultPromise = promise.new();

		local results = {};
		local size = #promises;
		
		local function handleSettle()
			if (size == 0) then 

				if (#results < 0) then
					return resultPromise:Reject("None of the specified promises were accepted");
				end

				return resultPromise:Resolve(results);
			end
		end

		local finalize = function(winner, result)
			size-=1;

			if (winner.status == "rejected") then
				return handleSettle();
			end
			table.insert(results, result);
			handleSettle();
		end

		for _, competingPromise in promises do 
			competingPromise:Finally(finalize);
		end

		return resultPromise;

	end,
	allSettled = function(promises: {Promise}): Promise -- Array of all promises with their status and resolution values

		local resultPromise = promise.new();

		local results = {};
		local size = #promises;

		local function handleSettle()

			if (size == 0) then 

				if (#results < 0) then
					return resultPromise:Reject("None of the specified promises were rejected or completed");
				end

				return resultPromise:Resolve(results);
			end
		end

		local finalize = function(winner, result)
			size-=1;
			table.insert(results, {status = winner.status, value = result});
			handleSettle();
		end

		for _, competingPromise in promises do 
			competingPromise:Finally(finalize);
		end

		return resultPromise;

	end,
	race = function(promises: {Promise}): Promise -- The first promise to settle
		
		local startTime = os.clock();
		local resultPromise = promise.new();
		
		local winnerFound = false;
		
		local finalize = function(winner, result)
			if (winnerFound) then return end;
			winnerFound = true;
			resultPromise:Resolve(result)
		end
		
		for _, competingPromise in promises do 
			competingPromise:Finally(finalize);
		end
		
		return resultPromise;
		
	end,
	any = function(promises: {Promise}): Promise -- The first promise to finish 

		local resultPromise = promise.new();

		local winnerFound = false;
		local size = #promises;

		local finalize = function(winner, result)
			size -= 1;
			if (winner.status == "rejected") then
				
				if (size == 0) then
					resultPromise:Reject("None of the specified promises were accepted");
				end
				
				return 
			end;
			if (winnerFound) then return end;
			winnerFound = true;
			resultPromise:Resolve(result)
		end

		for _, competingPromise in promises do 
			competingPromise:Finally(finalize);
		end

		return resultPromise;

	end,
	new = function(callback: (...any?) -> ...any?, ...): Promise
		
		local object = { 
			routine = callback and coroutine.create(callback) or nil,
			yieldTime = 0,
			callbacks = {},
			status = "pending",
		};
	
		if (callback) then
			task.spawn(asynchronousSafeExecutor, object, ...);
		end
		
		setmetatable(object, promise);

		return object;
	end,	
};
promise.__index = promise;

-- Memory Management

function promise:Clear()
	table.clear(self.callbacks);
	coroutine.close(self.routine);
	setmetatable(self, nil);
	self = nil;
end

-- Initialization

function promise:ScheduleAttempt(callback: (...any?) -> ...any?, delayTime: number, ...)
	
	self.status = "pending"

	self.routine = coroutine.create(callback);
	self.yieldTime = delayTime;

	task.spawn(asynchronousSafeExecutor, self, ...);
	
end


function promise:Attempt(callback: (...any?) -> ...any?, ...)

	self.status = "pending"
	self.routine = coroutine.create(callback);
	self.yieldTime = 0;

	task.spawn(asynchronousSafeExecutor, self, ...);

end

-- Resolution Handling

function promise:Finalize(status: boolean, ...)
	
	local ignoreType = status and "reject" or "resolve"; 
	local preUpdateStatus = self.status;
	
	local oldRoutine = self.routine;
	
	task.wait();
	-- Allow asynchronous safe function to close itself without triggering resolve (if the coroutine was resolved in the coroutine)
	
	for _, callback in pairs(self.callbacks) do

		if (callback.type == ignoreType or callback.type == "catch") then continue end;
		
		task.spawn(callback.callback, self, ...);
		
	end
	
	task.wait();
	
	if (preUpdateStatus == self.status) then
		-- If after all callbacks were called and the promise hasnt been re-attempted then clear all data
		self:Clear();
	end
	
end

-- Resolution Cases

function promise:Yield(length) -- Delay coroutine execution for time
	self.yieldTime += length;
	coroutine.yield();
end

function promise:Reject(...) -- Reject Promise
	self.status = "rejected";
	self:Finalize(false, ...);
end

function promise:Resolve(...) -- Accept Promise
	self.status = "fulfilled";
	self:Finalize(true, ...);
end

function promise:Cancel() -- Cancel Promise
	self.status = "rejected";
	promise:Finalize(false, "Cancelled");
end

-- Resolution Callback Instantiation

function promise:Then(resolve: (...any?) -> nil, reject: (...any?) -> nil) -- Resolution Success
	insertCallback(self, "resolve", resolve);
	
	if (not reject) then return end;
	insertCallback(self, "reject", reject);
end

function promise:Finally(callback: (...any?) -> nil) -- Resolution Failure
	insertCallback(self, "finally", callback);
end

function promise:Catch(callback: (...any?) -> nil) -- Promise Completion
	insertCallback(self, "catch", callback);
end

return promise;
