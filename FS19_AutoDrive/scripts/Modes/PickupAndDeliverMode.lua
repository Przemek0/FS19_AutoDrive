PickupAndDeliverMode = ADInheritsFrom(AbstractMode)

PickupAndDeliverMode.STATE_INIT = 1
PickupAndDeliverMode.STATE_PICKUP = 2
PickupAndDeliverMode.STATE_DELIVER = 3
PickupAndDeliverMode.STATE_RETURN_TO_START = 4
PickupAndDeliverMode.STATE_FINISHED = 5
PickupAndDeliverMode.STATE_EXIT_FIELD = 6

function PickupAndDeliverMode:new(vehicle)
    local o = PickupAndDeliverMode:create()
    o.vehicle = vehicle
    PickupAndDeliverMode.reset(o)
    return o
end

function PickupAndDeliverMode:reset()
    self.state = PickupAndDeliverMode.STATE_INIT
    self.loopsDone = 0
    self.activeTask = nil
end

function PickupAndDeliverMode:start()
	AutoDrive.debugPrint(self.vehicle, AutoDrive.DC_PATHINFO, "[AD] PickupAndDeliverMode:start start self.state %s", tostring(self.state))

    if not self.vehicle.ad.stateModule:isActive() then
        self.vehicle:startAutoDrive()
    end

    if self.vehicle.ad.stateModule:getFirstMarker() == nil or self.vehicle.ad.stateModule:getSecondMarker() == nil then
        return
    end

    self.activeTask = self:getNextTask()
    if self.activeTask ~= nil then
        self.vehicle.ad.taskModule:addTask(self.activeTask)
    end
	AutoDrive.debugPrint(self.vehicle, AutoDrive.DC_PATHINFO, "[AD] PickupAndDeliverMode:start end self.state %s", tostring(self.state))
end

function PickupAndDeliverMode:monitorTasks(dt)
end

function PickupAndDeliverMode:handleFinishedTask()
    self.vehicle.ad.trailerModule:reset()
    self.activeTask = self:getNextTask(true)
    if self.activeTask ~= nil then
        self.vehicle.ad.taskModule:addTask(self.activeTask)
    end
end

function PickupAndDeliverMode:stop()
end

function PickupAndDeliverMode:continue()
    if self.activeTask ~= nil and self.state == PickupAndDeliverMode.STATE_DELIVER or self.state == PickupAndDeliverMode.STATE_PICKUP or self.state == PickupAndDeliverMode.STATE_EXIT_FIELD then
        self.activeTask:continue()
    end
end

function PickupAndDeliverMode:getNextTask(forced)
    local nextTask
	AutoDrive.debugPrint(self.vehicle, AutoDrive.DC_PATHINFO, "[AD] PickupAndDeliverMode:getNextTask start self.state %s", tostring(self.state))

	local x, y, z = getWorldTranslation(self.vehicle.components[1].node)
	local point = nil
	local distanceToStart = 0
	if self.vehicle.ad ~= nil and ADGraphManager.getWayPointById ~= nil and self.vehicle.ad.stateModule ~= nil and self.vehicle.ad.stateModule.getFirstMarker ~= nil and self.vehicle.ad.stateModule:getFirstMarker() ~= nil and self.vehicle.ad.stateModule:getFirstMarker() ~= 0 and self.vehicle.ad.stateModule:getFirstMarker().id ~= nil then
		point = ADGraphManager:getWayPointById(self.vehicle.ad.stateModule:getFirstMarker().id)
		if point ~= nil then
			distanceToStart = MathUtil.vector2Length(x - point.x, z - point.z)
		end
	end

    local trailers, _ = AutoDrive.getTrailersOf(self.vehicle, false)
    local fillLevel, leftCapacity = AutoDrive.getFillLevelAndCapacityOfAll(trailers)
    local maxCapacity = fillLevel + leftCapacity
    local filledToUnload = (leftCapacity <= (maxCapacity * (1 - AutoDrive.getSetting("unloadFillLevel", self.vehicle) + 0.001)))

	if self.state == PickupAndDeliverMode.STATE_INIT then
		AutoDrive.debugPrint(self.vehicle, AutoDrive.DC_PATHINFO, "[AD] PickupAndDeliverMode:getNextTask STATE_INIT self.state %s distanceToStart %s", tostring(self.state), tostring(distanceToStart))
		if AutoDrive.checkIsOnField(x, y, z)  and distanceToStart > 30 then
			-- is activated on a field - use ExitFieldTask to leave field according to setting
			AutoDrive.debugPrint(self.vehicle, AutoDrive.DC_PATHINFO, "[AD] PickupAndDeliverMode:getNextTask set STATE_EXIT_FIELD")
			self.state = PickupAndDeliverMode.STATE_EXIT_FIELD
		elseif filledToUnload then	-- fill level above setting unload level
			AutoDrive.debugPrint(self.vehicle, AutoDrive.DC_PATHINFO, "[AD] PickupAndDeliverMode:getNextTask set STATE_PICKUP")
			self.state = PickupAndDeliverMode.STATE_PICKUP
		else
			-- fill capacity left - go to pickup
			AutoDrive.debugPrint(self.vehicle, AutoDrive.DC_PATHINFO, "[AD] PickupAndDeliverMode:getNextTask set STATE_DELIVER")
			self.state = PickupAndDeliverMode.STATE_DELIVER
		end
		AutoDrive.debugPrint(self.vehicle, AutoDrive.DC_PATHINFO, "[AD] PickupAndDeliverMode:getNextTask STATE_INIT end self.state %s", tostring(self.state))
	end

    if self.state == PickupAndDeliverMode.STATE_DELIVER then
		-- STATE_DELIVER - drive to load destination
		AutoDrive.debugPrint(self.vehicle, AutoDrive.DC_PATHINFO, "[AD] PickupAndDeliverMode:getNextTask STATE_DELIVER")
        if self.vehicle.ad.stateModule:getLoopCounter() == 0 or self.loopsDone < self.vehicle.ad.stateModule:getLoopCounter() then
			AutoDrive.debugPrint(self.vehicle, AutoDrive.DC_PATHINFO, "[AD] PickupAndDeliverMode:getNextTask LoadAtDestinationTask...")
            nextTask = LoadAtDestinationTask:new(self.vehicle, self.vehicle.ad.stateModule:getFirstMarker().id)
            self.state = PickupAndDeliverMode.STATE_PICKUP

            if AutoDrive.getSetting("distributeToFolder", self.vehicle) and AutoDrive.getSetting("useFolders") then
                if AutoDrive.getSetting("syncMultiTargets") then
					AutoDrive.debugPrint(self.vehicle, AutoDrive.DC_PATHINFO, "[AD] PickupAndDeliverMode:getNextTask syncMultiTargets true -> getNextTarget")
                    local nextTarget = ADMultipleTargetsManager:getNextTarget(self.vehicle, forced)
                    if nextTarget ~= nil then
						AutoDrive.debugPrint(self.vehicle, AutoDrive.DC_PATHINFO, "[AD] PickupAndDeliverMode:getNextTask setSecondMarker -> nextTarget")
                        self.vehicle.ad.stateModule:setSecondMarker(nextTarget)
                    end
                elseif forced then
					AutoDrive.debugPrint(self.vehicle, AutoDrive.DC_PATHINFO, "[AD] PickupAndDeliverMode:getNextTask setNextTargetInFolder")
                    self.vehicle.ad.stateModule:setNextTargetInFolder()
                end

                local trailers, _ = AutoDrive.getTrailersOf(self.vehicle, false)
                local fillLevel, _ = AutoDrive.getFillLevelAndCapacityOfAll(trailers)
                if fillLevel > 1 then
					AutoDrive.debugPrint(self.vehicle, AutoDrive.DC_PATHINFO, "[AD] PickupAndDeliverMode:getNextTask UnloadAtDestinationTask...")
                    nextTask = UnloadAtDestinationTask:new(self.vehicle, self.vehicle.ad.stateModule:getSecondMarker().id)
                    self.state = PickupAndDeliverMode.STATE_DELIVER
                end
            end
        else
			AutoDrive.debugPrint(self.vehicle, AutoDrive.DC_PATHINFO, "[AD] PickupAndDeliverMode:getNextTask DriveToDestinationTask...")
            nextTask = DriveToDestinationTask:new(self.vehicle, self.vehicle.ad.stateModule:getFirstMarker().id)
            self.state = PickupAndDeliverMode.STATE_RETURN_TO_START
        end
    elseif self.state == PickupAndDeliverMode.STATE_PICKUP then
		-- STATE_PICKUP - drive to unload destination
		AutoDrive.debugPrint(self.vehicle, AutoDrive.DC_PATHINFO, "[AD] PickupAndDeliverMode:getNextTask STATE_PICKUP UnloadAtDestinationTask...")
		nextTask = UnloadAtDestinationTask:new(self.vehicle, self.vehicle.ad.stateModule:getSecondMarker().id)
		self.loopsDone = self.loopsDone + 1
		self.state = PickupAndDeliverMode.STATE_DELIVER
    elseif self.state == PickupAndDeliverMode.STATE_EXIT_FIELD then
		-- is activated on a field - use ExitFieldTask to leave field according to setting
		AutoDrive.debugPrint(self.vehicle, AutoDrive.DC_PATHINFO, "[AD] PickupAndDeliverMode:getNextTask STATE_EXIT_FIELD ExitFieldTask...")
		nextTask = ExitFieldTask:new(self.vehicle)

		if filledToUnload then	-- fill level above setting unload level
			AutoDrive.debugPrint(self.vehicle, AutoDrive.DC_PATHINFO, "[AD] PickupAndDeliverMode:getNextTask set STATE_PICKUP")
			self.state = PickupAndDeliverMode.STATE_PICKUP
		else
			-- fill capacity left - go to pickup
			AutoDrive.debugPrint(self.vehicle, AutoDrive.DC_PATHINFO, "[AD] PickupAndDeliverMode:getNextTask set STATE_DELIVER")
			self.state = PickupAndDeliverMode.STATE_DELIVER
		end
    elseif self.state == PickupAndDeliverMode.STATE_RETURN_TO_START then
		AutoDrive.debugPrint(self.vehicle, AutoDrive.DC_PATHINFO, "[AD] PickupAndDeliverMode:getNextTask STATE_RETURN_TO_START StopAndDisableADTask...")
        nextTask = StopAndDisableADTask:new(self.vehicle, ADTaskModule.DONT_PROPAGATE)
        self.state = PickupAndDeliverMode.STATE_FINISHED
    end

	AutoDrive.debugPrint(self.vehicle, AutoDrive.DC_PATHINFO, "[AD] PickupAndDeliverMode:getNextTask end self.state %s", tostring(self.state))
    return nextTask
end

function PickupAndDeliverMode:shouldUnloadAtTrigger()
    return self.state == PickupAndDeliverMode.STATE_DELIVER
end

function PickupAndDeliverMode:shouldLoadOnTrigger()
    return (self.state == PickupAndDeliverMode.STATE_PICKUP) and (AutoDrive.getDistanceToTargetPosition(self.vehicle) <= AutoDrive.getSetting("maxTriggerDistance"))
end
