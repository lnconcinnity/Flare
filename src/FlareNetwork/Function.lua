local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Remote = require(script.Parent.Remote)

local EMPTY_CALLBACK = function(...)
    return ...
end
local IS_SERVER = RunService:IsServer()

local FunctionAPI = {}
if IS_SERVER then
    function FunctionAPI:InvokeClient(player: Player, ...)
        local threadId = HttpService:GenerateGUID(false)
        local currentThread =  coroutine.running()
        local disconnect; disconnect = self._recieve:Connect(function(boundId: string, ...)
            if boundId == threadId then
                disconnect()
                task.spawn(currentThread, ...)
            end
        end)
        self._waitingThreads[threadId] = {thread = currentThread, cleanup = disconnect, lifetime = self.RequestTimeout}
        self._send:FireClient(player, threadId, ...)
        return coroutine.yield()
    end
else
    function FunctionAPI:InvokeServer(...)
        local threadId = HttpService:GenerateGUID(false)
        local currentThread =  coroutine.running()
        local disconnect; disconnect = self._recieve:Connect(function(boundId: string, ...)
            if boundId == threadId then
                disconnect()
                task.spawn(currentThread, ...)
            end
        end)
        self._waitingThreads[threadId] = {thread = currentThread, cleanup = disconnect, lifetime = self.RequestTimeout}
        self._send:FireServer(threadId, ...)
        return coroutine.yield()
    end
end

function FunctionAPI:Destroy()
    self._sendCleanup()
    self._sendCleanup = nil
    self._send:Destroy()
    self._recieve:Destroy()
    self._threadManager:Disconnect()
    self._threadManager = nil
    for _, context in pairs(self._waitingThreads) do
        -- drop all request
        task.spawn(context.thread)
        context.cleanup()
    end
    self._waitingThreads = nil
    setmetatable(self, nil)
end

local Function = {}
Function.__index = FunctionAPI
function Function.new(functionName: string, defaultTimeout: number?)
    local self = {}
    self.Name = functionName
    self.RequestTimeout = defaultTimeout or 8
    self.OnInvoke = EMPTY_CALLBACK
    self._recieve = Remote.new(functionName.."Recieve", false)
    self._send = Remote.new(functionName.."Send", false)
    self._sendCleanup = self._send:Connect(function(...)
        local args = {...}
        local threadId = table.remove(args, if IS_SERVER then 2 else 1)
        if IS_SERVER then
            local player = args[1]
            self._send:FireClient(player, threadId, self.OnInvoke(player, table.unpack(args, 2)))
        else
            self._send:FireServer(threadId, self.OnInvoke(table.unpack(args)))
        end
    end)
    self._waitingThreads = {} :: {[string]: {thread: thread, lifetime: number, cleanup: () -> ()}}
    self._threadManager = RunService.Heartbeat:Connect(function(dt)
        for threadId: string, context: {thread: thread, lifetime: number, cleanup: () -> ()} in pairs(self._waitingThreads) do
            if context.lifetime > 0 then
                context.lifetime -= dt
            else
                self._waitingThreads[threadId] = nil
                task.spawn(context.thread)
                context.cleanup()
            end
        end
    end)
    setmetatable(self, Function)
    return self
end

return Function