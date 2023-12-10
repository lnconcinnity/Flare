local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local FlareClass = require(script.Parent.Utility.FlareClass)

type ActorRef = {Actor: Actor, IsWorking: boolean, IsTemporary: boolean?, RefKey: string,}

local IS_SERVER = RunService:IsServer()
local MAX_ACTOR_COUNT = 128

local bin = script:WaitForChild("ActorBin")
bin.Parent = if IS_SERVER then game:GetService("ServerScriptService") else game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts")

local templatesContainer = script:WaitForChild("SubscriberTemplates")
local subscriberTemplate: Script | LocalScript = if IS_SERVER then templatesContainer:WaitForChild("ServerSubscriber") else templatesContainer:WaitForChild("ClientSubscriber")

local ActorPool = FlareClass.extend()
function ActorPool:FlareInit(targetFactory: ModuleScript, actorCount: number?)
    assert(typeof(targetFactory) == "Instance" and targetFactory:IsA("ModuleScript"), "Argument 2 must be of a module script!")
    self.WarnAsyncUsage = true
    self._factoryId = HttpService:GenerateGUID(false)
    self._factoryReference = targetFactory
    self._actors = {
        working = {},
        haltedThreads = {},
    } :: {[string]: ActorRef, haltedThreads: {[number]: thread}, working: {[string]: ActorRef}}
    for _ = 1, math.min(MAX_ACTOR_COUNT, actorCount) do
        self:_allocateWorker(true)
    end
end

function ActorPool:_allocateWorker(initActor: boolean?)
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
            self._actors.working[workerId] = nil
            actorInstance:Destroy()
        end))
    end
    return actorRef
end

function ActorPool:_getWorker(fromAsync: boolean): (ActorRef)
    local recentActor = self._actors[#self._actors]
    if recentActor then
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

function ActorPool:_freeWorker(actorRef: ActorRef)
    if self._actors.working[actorRef.RefKey] then
        if not actorRef.IsTemporary then
            local pendingWork = self._actors.haltedThreads[#self._actors.haltedThreads]
            if pendingWork then
                self._actors.haltedThreads[#self._actors.haltedThreads] = nil
                task.spawn(pendingWork, actorRef)
                return "Pended"
            end
        end
        actorRef.IsWorking = false
        self._actors.working[actorRef.RefKey] = nil
        self._actors[#self._actors+1] = actorRef
    end
    return "Free"
end

function ActorPool:_taskWorker(actorRef: ActorRef, target: string, ...: any): (...any)
    debug.profilebegin("Task Worker<" .. target .. ">")
    actorRef.IsWorking = true
    local taskId = HttpService:GenerateGUID(false)
    local subscriber = actorRef.Actor:WaitForChild("Subscriber")
    subscriber.RequestStart:Fire({task = taskId, target = target, args = {...}})
    local conn = nil
    local thread = coroutine.running()
    conn = (subscriber.RequestEnd :: BindableEvent).Event:Connect(self:_BYPASS_ACCESS_IDENTIFIERS_FOR(function(refId: string, ...: any)
        if refId == taskId then
            self:_freeWorker(actorRef)
            task.spawn(thread, ...)
            conn:Disconnect()
        end
    end))
    debug.profilebegin("Task Worker<" .. target .. ">")
    return coroutine.yield()
end

function ActorPool:Request(target: string, ...: any): (...any)
    assert(type(target) == "string", "Argument 1 must reference the factory's member function to intiate a parallel task")
    local actorRef = self:_getWorker(false)
    return self:_taskWorker(actorRef, target, ...)
end

function ActorPool:RequestAsync(target: string, ...: any): (...any)
    if self.WarnAsyncUsage then
        warn("This method is much more expensive in terms of performance than setting the actor count to a much more higher amount at initialization!")
    end
    assert(type(target) == "string", "Argument 1 must reference the factory's member function to intiate a parallel task")
    local actorRef = self:_getWorker(true)
    return self:_taskWorker(actorRef, target, ...)
end

ActorPool.post()
return ActorPool