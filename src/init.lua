local RunService = game:GetService("RunService")

local Siganl = require(script.Utility.Signal)
local Promise = require(script.Utility.Promise)
local Symbol = require(script.Utility.Symbol)
local FlareNetwork = require(script.FlareNetwork)
local Instances = require(script.Instances)

local IS_SERVER = RunService:IsServer()

local HasFlareStarted, FlareStartedEvent = false, Siganl.new()

local FlareObjectsContainer = {}
local Flare = {}
Flare.Identifiers = {
    EventMarker = Symbol("NetEvent"),
    UnreliableEventMarker = Symbol("UnreliableNetEvent"),
    FunctionMarker = Symbol("NetFunction")
}
Flare.Utility = script.Utility
if IS_SERVER then
    function Flare.GetService(serviceName: string): any
        assert(HasFlareStarted, "Flare.GetService() can only be used after Flare has started (via Flare.Start()).")
        return assert(FlareObjectsContainer[serviceName], `Service {serviceName} does not exist`)
    end
    
    function Flare.CreateService(serviceName: string, networkingContext: {any}): any
        assert(#serviceName > 0, "Argument 1 must be a non-empty string")
        assert(not FlareObjectsContainer[serviceName], `{serviceName} already exists`)
        local flareService = Instances.GetFlareObject()
        flareService.Name = serviceName
        if networkingContext then
            flareService.Client = networkingContext
        end
        FlareObjectsContainer[serviceName] = flareService
        return flareService
    end
else
    local replicatedServices = {}
    function Flare.GetService(serviceName: string): any
        assert(HasFlareStarted, "Flare.GetService() can only be used after Flare has started (via Flare.Start()).")
            if FlareNetwork.has(serviceName) then
            if replicatedServices[serviceName] then
                return replicatedServices[serviceName]
            end
            local net = FlareNetwork.new(serviceName)
            replicatedServices[serviceName] = net
            return net
        end
        error(`{serviceName}[Network] does not exist`)
    end

    function Flare.GetController(controllerName: string): any
        assert(HasFlareStarted, "Flare.GetController() can only be used after Flare has started (via Flare.Start()).")
        return assert(FlareObjectsContainer[controllerName], `Service {controllerName} does not exist`)
    end

    function Flare.CreateController(controllerName: string)
        assert(#controllerName > 0, "Argument 1 must be a non-empty string")
        assert(not FlareObjectsContainer[controllerName], `{controllerName} already exists`)
        local flareController = Instances.GetFlareObject()
        flareController.Name = controllerName
        FlareObjectsContainer[controllerName] = flareController
        return flareController
    end
end

function Flare.LoadDescendants(group: Instance): {any}
    local loaded = {}
    local descendants = group:GetDescendants()
    for k = #descendants, 1, -1 do
        if k:IsA("ModuleScript") then
            local ok, object = xpcall(require, warn, descendants[k])
            if ok then
                loaded[#loaded+1] = object
            end
        end
    end
    return loaded
end

function Flare.OnStarted()
    if HasFlareStarted then
        return Promise.resolve()
    else
        return Promise.fromEvent(FlareStartedEvent)
    end
end

function Flare.Start()
    return Promise.new(function(resolve)
        local finished = {}
        for name, object in pairs(FlareObjectsContainer) do
            table.insert(finished, Promise.new(function(r)
                -- allow function overloading
                local realObject = object.new()
                if IS_SERVER then
                    if object.Client then
                        local net = FlareNetwork.new(object.Name)
                        for key, marker in pairs(object.Client) do
                            if marker == Flare.Identifiers.EventMarker then
                                net:MakeEvent(key, false)
                            elseif marker == Flare.Identifiers.UnreliableEventMarker then
                                net:MakeEvent(key, true)
                            elseif marker == Flare.Identifiers.FunctionMarker then
                                net:MakeFunction(key)
                            end
                        end
                        realObject.Client = net
                    end
                end
                FlareObjectsContainer[name] = realObject
                r(realObject)
            end):catch(warn))
        end
        HasFlareStarted = true
        FlareStartedEvent:Fire()
        FlareStartedEvent:Destroy()
        Promise.all(finished):catch(warn):andThen(function(initObjects)
            for _, object in ipairs(initObjects) do
                if object.FlareStart then
                    task.spawn(object.FlareStart, object)
                end
            end
        end)
        resolve()
    end)
end

return Flare