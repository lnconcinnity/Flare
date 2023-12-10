local RunService = game:GetService("RunService")

local Function = require(script.Function)
local Remote = require(script.Remote)

local FlareClass = require(script.Parent.Utility.FlareClass)

local IS_SERVER = RunService:IsServer()

local function GetMarker(markerName: string, parent: Instance?): Configuration
    local marker = script:FindFirstChild(markerName)
    if not marker then
        marker = Instance.new("Configuration")
        marker.Name = markerName
        marker.Parent = parent or script
    end
    return marker
end
local NetworksContainer = if IS_SERVER then GetMarker("Networks") else script:WaitForChild("Networks")

local FlareNetwork = FlareClass.extend()
function FlareNetwork.has(networkName: string)
    return NetworksContainer:FindFirstChild(networkName) ~= nil
end

function FlareNetwork:FlareInit(networkName: string)
    self._events = {}
    self._functions = {}
    if IS_SERVER then
        self._marker = GetMarker(networkName, NetworksContainer)
    else
        local marker = assert(NetworksContainer:FindFirstChild(networkName), `{networkName} does not exist`)
        local existingMarkers = marker:GetAttributes()
        for key, value in pairs(existingMarkers) do
            local isEvent = key:sub(#key) == 'E'
            key = key:sub(1, #key-1)
            self[if isEvent then "MakeEvent" else "MakeFunction"](self, key, value)
        end
    end
end

function FlareNetwork:MakeEvent(eventName: string, unreliable: boolean?)
    if not IS_SERVER and not self:_IS_INTERNALLY_CALLED() then
        error("Cannot call exposed internal.")
    end
    local event = Remote.new(eventName, unreliable)
    self._events[eventName] = event
    self[eventName] = event
    if IS_SERVER then
        self._marker:SetAttribute(eventName..'E', unreliable == true)
    end
    return event
end

function FlareNetwork:RemoveEvent(eventName: string)
    if not IS_SERVER and not self:_IS_INTERNALLY_CALLED() then
        error("Cannot call exposed internal.")
    end
    self[eventName] = nil
    local existing = self._events[eventName]
    if existing then
        existing:Destroy()
    end
    if IS_SERVER then
        self._marker:SetAttribute(eventName..'E', nil)
    end
    self._events[eventName] = nil
end

function FlareNetwork:MakeFunction(functionName: string, defaultTimeout: number?)
    if not IS_SERVER and not self:_IS_INTERNALLY_CALLED() then
        error("Cannot call exposed internal.")
    end
    local fn = Function.new(functionName, defaultTimeout)
    self._functions[functionName] = fn
    self[functionName] = fn
    if IS_SERVER then
        self._marker:SetAttribute(functionName..'F', fn.RequestTimeout)
    end
    return fn
end

function FlareNetwork:RemoveFunction(functionName: string)
    if not IS_SERVER and not self:_IS_INTERNALLY_CALLED() then
        error("Cannot call exposed internal.")
    end
    self[functionName] = nil
    local existing = self._functions[functionName]
    if existing then
        existing:Destroy()
    end
    if IS_SERVER then
        self._marker:SetAttribute(functionName..'F', nil)
    end
    self._functions[functionName] = nil
end

function FlareNetwork:Destroy()
    if IS_SERVER then
        self._marker:Destroy()
    else
        self._marker = nil
    end
    for k, e in pairs(self._events) do
        e:Destroy()
        self[k] = nil
    end
    for k, f in pairs(self._functions) do
        f:Destroy()
        self[k] = nil
    end
    self:_INTERNAL_CLEANUP()
    setmetatable(self, nil)
end

return FlareNetwork