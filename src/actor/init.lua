local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

type ActorRef = {Actor: Actor, IsWorking: boolean, IsTemporary: boolean?, RefKey: string,}

local IS_SERVER = RunService:IsServer()
local MAX_ACTOR_COUNT = 128

local bin = nil
if IS_SERVER then
    bin = script:WaitForChild("ActorBin"):Clone()
    bin.Parent = game:GetService("ServerScriptService")
else
    bin = script:WaitForChild("ActorBin")
    bin.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts")
end

local templatesContainer = script:WaitForChild("SubscriberTemplates")
local subscriberTemplate: Script | LocalScript = if IS_SERVER then templatesContainer:WaitForChild("ServerSubscriber") else templatesContainer:WaitForChild("ClientSubscriber")

local ActorPoolMetatable = {}
ActorPoolMetatable.__index = ActorPoolMetatable
function ActorPoolMetatable:_allocateWorker(initActor: boolean?)
    local workerId = HttpService:GenerateGUID(false)
    local actorIndex = #self._actors+1
    local actorInstance = Instance.new("Actor")
    actorInstance.Name = string.format("[%s]Actor%i", self._factoryId, actorIndex)
    local subscriber = subscriberTemplate:Clone()
    subscriber.Name = "Subscriber";
    (subscriber:WaitForChild("FactoryReference") :: ObjectValue).Value = self._factoryReference

    subscriber.Disabled = false
    subscriber.Parent = actorInstance
    actorInstance.Parent = bin
    local actorRef = {
        Actor = actorInstance,
        IsWorking = false,
        IsTemporary = not initActor,
        RefKey = workerId,
    }
    if type(initActor) == "boolean" and initActor == true then
        self._actors[actorIndex] = actorRef
    else
        -- automatically destroy the temporary actor
        (subscriber:WaitForChild("RequestEnd") :: BindableEvent).Event:Connect(self:_BYPASS_ACCESS_IDENTIFIERS_FOR(function()
            self._actors.working[workerId].Actor = nil
            self._actors.working[workerId] = nil
            actorInstance:Destroy()
        end))
    end
    return actorRef
end

function ActorPoolMetatable:_getWorker(fromAsync: boolean, fromDirectActor: Actor?): (ActorRef)
    local recentActor = self._actors[#self._actors]
    if fromDirectActor ~= nil then
        local indexAt = -1
        -- find if it's not active
        for i = #self._actors, 1, -1 do
            local ref = self._actors[i]
            if ref.Actor == fromDirectActor then
                indexAt = i
                break
            end
        end
        if indexAt > 0 then
            -- untask the actor
            local actor = table.remove(self._actors, indexAt)
            self._actors.working[actor.RefKey] = actor
            return actor
        else
            local thread = coroutine.running()
            table.insert(self._actors.haltedThreads, {thread = thread, target = fromDirectActor})
            return coroutine.yield()
        end
    elseif recentActor then
        self._actors[#self._actors] = nil
        self._actors.working[recentActor.RefKey] = recentActor
        return recentActor
    else
        if fromAsync then
            local tempWorker = self:_allocateWorker(false)
            return tempWorker
        else
            local thread = coroutine.running()
            table.insert(self._actors.haltedThreads, thread)
            return coroutine.yield()
        end
    end
end

function ActorPoolMetatable:_freeWorker(actorRef: ActorRef)
    if self._actors.working[actorRef.RefKey] then
        if not actorRef.IsTemporary then
            local pendingWork = self._actors.haltedThreads[#self._actors.haltedThreads]
            if pendingWork then
                local isTable = type(pendingWork) == "table"
                if (isTable and typeof(pendingWork.target) == "Instance" and pendingWork.target:IsA("Actor")) and pendingWork.target == actorRef.Actor then
                    self._actors.haltedThreads[#self._actors.haltedThreads] = nil
                    task.spawn(pendingWork.thread, actorRef)
                    return "Pended"
                elseif not isTable then
                    self._actors.haltedThreads[#self._actors.haltedThreads] = nil
                    task.spawn(pendingWork, actorRef)
                    return "Pended"
                end
            end
            actorRef.IsWorking = false
            self._actors.working[actorRef.RefKey] = nil
            self._actors[#self._actors+1] = actorRef
        end
    end
    return "Free"
end

function ActorPoolMetatable:_taskWorker(actorRef: ActorRef, target: string, ...: any): (...any)
    debug.profilebegin("Task Worker<" .. target .. ">")
    actorRef.IsWorking = true
    local taskId = HttpService:GenerateGUID(false)
    local subscriber = actorRef.Actor:WaitForChild("Subscriber")
    subscriber.RequestStart:Fire({task = taskId, target = target, args = {...}})
    local conn = nil
    local thread = coroutine.running()
    conn = (subscriber.RequestEnd :: BindableEvent).Event:Connect(function(refId: string, ...: any)
        if refId == taskId then
            self:_freeWorker(actorRef)
            task.spawn(thread, ...)
            conn:Disconnect()
        end
    end)
    debug.profilebegin("Task Worker<" .. target .. ">")
    return coroutine.yield()
end

function ActorPoolMetatable:DirectRequest(actor: Actor, target: string, ...: any): (...any)
    assert(type(target) == "string", "Argument 2 must reference the factory's member function to intiate a parallel task")
    local actorRef = self:_getWorker(false, actor)
    return self:_taskWorker(actorRef, target, ...)
end

function ActorPoolMetatable:Request(target: string, ...: any): (...any)
    assert(type(target) == "string", "Argument 1 must reference the factory's member function to intiate a parallel task")
    local actorRef = self:_getWorker(false, nil)
    return self:_taskWorker(actorRef, target, ...)
end

function ActorPoolMetatable:RequestAsync(target: string, ...: any): (...any)
    if self.WarnAsyncUsage then
        warn("This method is much more expensive in terms of performance than setting the actor count to a much more higher amount at initialization!")
    end
    assert(type(target) == "string", "Argument 1 must reference the factory's member function to intiate a parallel task")
    local actorRef = self:_getWorker(true, nil)
    return self:_taskWorker(actorRef, target, ...)
end

local ActorPool = {}
function ActorPool.new(targetFactory: ModuleScript, actorCount: number?)
    assert(typeof(targetFactory) == "Instance" and targetFactory:IsA("ModuleScript"), "Argument 2 must be of a module script!")
    local self = {}
    self.WarnAsyncUsage = true
    self._factoryId = HttpService:GenerateGUID(false)
    self._factoryReference = targetFactory
    self._actors = {
        working = {},
        haltedThreads = {},
    } :: {[string]: ActorRef, haltedThreads: {[number]: thread}, working: {[string]: ActorRef}}
    setmetatable(self, ActorPoolMetatable)
    for _ = 1, math.min(MAX_ACTOR_COUNT, actorCount) do
        self:_allocateWorker(true)
    end
    return self
end

return ActorPool