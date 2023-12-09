local RunService = game:GetService("RunService")

local Function = require(script.Function)
local Remote = require(script.Remote)

local FlareClass = require(script.Parent.Utility.FlareClass)

local function GetMarker(markerName: string): Configuration
    local marker = script:FindFirstChild(markerName)
    if not marker then
        marker = Instance.new("Configuration")
        marker.Parent = script
    end
    return marker
end

local IS_SERVER = RunService:IsServer()

local FlareNetwork = FlareClass.extend()
function FlareNetwork:FlareInit(networkName: string)
    self._events = {}
    self._functions = {}
    if IS_SERVER then
        self._marker = GetMarker(networkName)
    else
        local marker = script:WaitForChild(networkName)
        local existingMarkers = marker:GetAttributes()
        for key, value in pairs(existingMarkers) do
            local isEvent = key:sub(#key-1) == '.E'
            key = key:sub(1, #key-2)
            self[if isEvent then "MakeEvent" else "MakeFunction"](self, value)
        end
    end
end

function FlareNetwork:MakeEvent(eventName: string, unreliable: boolean?)
    if not IS_SERVER then
        self:_VERIFY_EXPOSED_PRIVATE()
    end
    local event = Remote.new(eventName, unreliable)
    self._events[eventName] = event
    self[eventName] = event
    if IS_SERVER then
        self._marker:SetAttribute(eventName..'.E', unreliable == true)
    end
    return event
end

function FlareNetwork:RemoveEvent(eventName: string)
    self[eventName] = nil
    local existing = self._events[eventName]
    if existing then
        existing:Destroy()
    end
    if IS_SERVER then
        self._marker:SetAttribute(eventName..'.E', nil)
    end
    self._events[eventName] = nil
end

function FlareNetwork:MakeFunction(functionName: string, defaultTimeout: number?)
    local fn = Function.new(functionName, defaultTimeout)
    self._functions[functionName] = fn
    self[functionName] = fn
    if IS_SERVER then
        self._marker:SetAttribute(functionName..'.F', fn.RequestTimeout)
    end
    return fn
end

function FlareNetwork:RemoveFunction(functionName: string)
    self[functionName] = nil
    local existing = self._functions[functionName]
    if existing then
        existing:Destroy()
    end
    if IS_SERVER then
        self._marker:SetAttribute(functionName..'.F', nil)
    end
    self._functions[functionName] = nil
end

function FlareNetwork:Destroy()
    if IS_SERVER then
        self._marker:Destroy()
        
    end
end

return FlareNetwork