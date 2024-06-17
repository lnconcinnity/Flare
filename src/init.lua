local RunService = game:GetService("RunService")

local Symbol = require(script.util.Symbol)
local Promise = require(script.util.Promise)
local FlareActorPool = require(script.actor)
local FlareNetworking = require(script.networking)
local FlareValue = require(script.private.FlareValue)
local FlareClass = require(script.private.FlareClass)

type DefaultObject = {
    Name: string,
    Client: {[string]: FlareNetworking.FlareRemote} | nil,
}
export type FlareRemotePacketData = FlareNetworking.FlareRemotePacketData
export type FlareValue<T> = FlareValue.FlareValue<T>
export type FlareClass<T, U> = FlareClass.FlareClass<T, U>
export type FlareObject = DefaultObject & FlareClass.FlareClass<any, any>
export type FlareOptions = {
    Name: string,
    StrictC: boolean?, -- should it mimic how C Classes work?
    Network: {
        [string]: Symbol.Symbol<string>
    }
}

local IS_SERVER = RunService:IsServer()
local FLARE_REMOTE_TYPES = {
    Reliable = Symbol("Reliable"), Unreliable = Symbol("Unreliable"), Requester = Symbol("Requester")
}

local HasFlareStarted = false
local FlareStarted = Instance.new("BindableEvent")
local FlareDependencies = {}

local Flare = {
    Util = {},
    NetworkPacket = FlareNetworking.Packet,
    MakeFlareValue = FlareValue.new,
    MakeActorPool = FlareActorPool.new,
    MakeFlareClass = FlareClass.new,
    CreateReliableRemote = function(packet)
        return {type = FLARE_REMOTE_TYPES.Reliable, packet = packet}
    end,
    CreateUnreliableRemote = function(packet)
        return {type = FLARE_REMOTE_TYPES.Unreliable, packet = packet}
    end,
    CreateRemoteRequester = function(packet)
        return {type = FLARE_REMOTE_TYPES.Requester, packet = packet}
    end,
}
for _, flareUtil in script.util:GetChildren() do
    local ok, dep = xpcall(require, warn, flareUtil)
    if ok then
        Flare.Util[flareUtil.Name] = dep
    end
end

if not IS_SERVER then
    local FlareServices = {}
    function Flare.CreateController(options: FlareOptions): FlareObject | DefaultObject
        assert(#options.Name > 0, 'argument 1 must a non-empty string')
        local flareObject = if options.StrictC == true then FlareClass.new() else {}
        flareObject.Name = options.Name
        FlareDependencies[options.Name] = flareObject
        return flareObject
    end

    function Flare.GetController(controllerName: string): FlareObject | DefaultObject
        assert(#controllerName > 0, 'argument 1 must a non-empty string')
        return FlareDependencies[controllerName]
    end

    function Flare.GetService(serviceName: string)
        if not FlareServices[serviceName] then
            local service = FlareNetworking.new(serviceName)
            service:Build()
            FlareServices[serviceName] = service
        end
        return FlareServices[serviceName]
    end
else
    function Flare.CreateService(options: FlareOptions): FlareObject | DefaultObject
        assert(#options.Name > 0, 'argument 1 must a non-empty string')
        local flareObject = if options.StrictC == true then FlareClass.new() else {}
        flareObject.Name = options.Name
        flareObject.Client = options.Network
        FlareDependencies[options.Name] = flareObject
        return flareObject
    end

    function Flare.GetService(serviceName: string): FlareObject | DefaultObject
        assert(#serviceName > 0, 'argument 1 must a non-empty string')
        return FlareDependencies[serviceName]
    end
end

function Flare.LoadDependencies(group: Instance): {any}
    local loaded = {}
    local descendants = group:GetDescendants()
    for k = #descendants, 1, -1 do
        if descendants[k]:IsA("ModuleScript") then
            local ok, object = xpcall(require, warn, descendants[k])
            if ok then
                loaded[#loaded+1] = object
            end
        end
    end
    return loaded
end

function Flare.Start()
    if HasFlareStarted then
        return Promise.resolve()
    end
    return Promise.new(function(resolve)
        local initDependencies = {}
        for dependencyName, dependency in FlareDependencies do
            initDependencies[#initDependencies+1] = Promise.new(function(r)
                if IS_SERVER and dependency.Client then
                    local group = FlareNetworking.new(dependency.Name)
                    for key, data in pairs(dependency.Client) do
                        group:MakeRemote(key, data.type == FLARE_REMOTE_TYPES.Reliable, data.type == FLARE_REMOTE_TYPES.Requester, data.packet)
                    end
                    dependency.Client = group
                end
                if type(dependency.new) == "function" then
                    dependency = dependency.new()
                    FlareDependencies[dependencyName] = dependency
                elseif type(dependency.FlareInit) == "function" then
                    task.spawn(dependency.FlareInit, dependency)
                end
                r(dependency)
            end):catch(warn)
        end
        Promise.all(initDependencies):catch(warn):andThen(function(inits)
            for _, init in inits do
                if type(init.FlareStart) == "function" then
                    task.spawn(init.FlareStart, init)
                end
            end
        end)
        HasFlareStarted = true
        FlareStarted:Fire()
        FlareStarted:Destroy()
        resolve()
    end)
end

function Flare.OnStart()
    if HasFlareStarted then
        return Promise.resolve()
    else
        return Promise.fromEvent(FlareStarted.Event)
    end
end

return Flare