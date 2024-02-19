-- PacketParser.lua, BufferWriter.lua, Channel.lua and Remote.lua were originally of ffrostfall's ByteNet networking system; repurposed for my own uses

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Hash = require(script.Parent.Parent.Utility.Hash)
local Channel = require(script.Parent.Parent.Utility.Channel)
local PacketParser = require(script.Parent.PacketParser)

local IS_SERVER = RunService:IsServer()

local EVENTS = script.Parent:WaitForChild("RemoteEvents")
local RELIABLE_EVENT, UNRELIABLE_EVENT = EVENTS:FindFirstChild("ReliableNetwork") :: RemoteEvent, EVENTS:FindFirstChild("UnreliableNetwork") :: UnreliableRemoteEvent

local RunningRemotes = {}
local MissingRemoteLogs = {}

local ProcessRecievedPacket: ({target: string, debugName: string, recipient: Player?, args: {any}}) = nil do
    local freePacketRecievedThread: thread? = nil

    local function passer(callback: (...any) -> (), recievedArgs: {any}, player: Player?)
        local acquiredRecievedPacketThread = freePacketRecievedThread
        freePacketRecievedThread = nil
        if IS_SERVER then
            recievedArgs = {player, table.unpack(recievedArgs)}
        end
        callback(table.unpack(recievedArgs))
        freePacketRecievedThread = acquiredRecievedPacketThread
    end

    local function yielder()
        while true do
            passer(coroutine.yield())
        end
    end
    
    function ProcessRecievedPacket(packetInfo: {target: string, debugName: string, recipient: Player?, args: {any}})
        local foundRemote = RunningRemotes[packetInfo.target]
        if not foundRemote or #foundRemote._listeners <= 0 then
            MissingRemoteLogs[packetInfo.target] = (MissingRemoteLogs[packetInfo.target] or 0) + 1
            local cur = MissingRemoteLogs[packetInfo.target]
            error(`Fired Remote [{packetInfo.debugName:sub(1, #packetInfo.debugName-2) .. (if packetInfo.debugName:sub(#packetInfo.debugName-1) == ".R" then "(ReliableChannel)" else "(UnreliableChannel)")}] {cur} times with no bound connection. Have you bind the remote with :Connect()?`)
        end
        for _, boundFn: (...any) -> () in ipairs(foundRemote._listeners) do
            if not freePacketRecievedThread then
                freePacketRecievedThread = coroutine.create(yielder)
                task.spawn(freePacketRecievedThread)
            end
            task.spawn(freePacketRecievedThread, boundFn, packetInfo.args, packetInfo.recipient)
        end
    end
end

local RemoteAPI = {}
if IS_SERVER then
    local OutgoingPacketsStream = {
        GlobalOutgoingPackets = Channel.new(),
        PlayerStreams = {},
    }

    function RemoteAPI:FireClient(player: Player, ...)
        local stream = OutgoingPacketsStream.PlayerStreams[player]
        if stream then
            stream:add({target = self._id, debugName = `{self.Name..self._type}`, unreliable = self._unreliable, args = {...}})
        end
    end

    function RemoteAPI:FireAllClients(...)
        OutgoingPacketsStream.GlobalOutgoingPackets:add({target = self._id, debugName = `{self.Name..self._type}`, unreliable = self._unreliable, args = {...}})
    end

    function RemoteAPI:FireForClients(players: {Player}, ...)
        local toDict = {}
        for j = 1, #players do
            toDict[players[j]] = true
        end
        self:FirePredicate(function(player)
            return toDict[player] ~= nil
        end, ...)
        toDict = nil
    end

    function RemoteAPI:FireAllClientsExcept(except: Player, ...)
        self:FirePredicate(function(player)
            return player ~= except
        end, ...)
    end

    function RemoteAPI:FirePredicate(predicate: (player: Player) -> (boolean), ...)
        for _, player in ipairs(Players:GetPlayers()) do
            if predicate(player) then
                self:FireClient(player, ...)
            end
        end
    end

    local function bindRemoteEvent(event: RemoteEvent | UnreliableRemoteEvent)
        event.OnServerEvent:Connect(function(player: Player, recievedBuffer: any)
            PacketParser.ProcessIn(recievedBuffer, ProcessRecievedPacket, player)
        end)
    end
    bindRemoteEvent(RELIABLE_EVENT)
    bindRemoteEvent(UNRELIABLE_EVENT)

    local function onPlayerAdded(player: Player)
        OutgoingPacketsStream.PlayerStreams[player] = Channel.new()
    end
    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(function(player: Player)
        local existing = OutgoingPacketsStream.PlayerStreams[player]
        if existing then
            existing:Destroy()
        end
        OutgoingPacketsStream.PlayerStreams[player] = nil
    end)
    for _, existingPlayer in ipairs(Players:GetPlayers()) do
        task.spawn(onPlayerAdded, existingPlayer)
    end
    RunService.Heartbeat:Connect(function(_dt)
        local globalReliable, globalUnreliable = PacketParser.ProcessOut(OutgoingPacketsStream.GlobalOutgoingPackets:flush())
        for player, stream in pairs(OutgoingPacketsStream.PlayerStreams) do
            if globalReliable then
                stream:add(globalReliable)
            end
            if globalUnreliable then
                stream:add(globalUnreliable)
            end

            local playerReliable, playerUnreliable = PacketParser.ProcessOut(stream:flush())
            if playerReliable then
                RELIABLE_EVENT:FireClient(player, playerReliable)
            end
            if playerUnreliable then
                UNRELIABLE_EVENT:FireClient(playerUnreliable, playerUnreliable)
            end
        end
    end)
else
    local OutgoingPackets = Channel.new()

    function RemoteAPI:FireServer(...)
        OutgoingPackets:add({target = self._id, debugName = `{self.Name..self._type}`, unreliable = self._unreliable, args = {...}})
    end

    local function bindRemoteEvent(event: RemoteEvent | UnreliableRemoteEvent)
        event.OnClientEvent:Connect(function(recievedBuffer: any)
            PacketParser.ProcessIn(recievedBuffer, ProcessRecievedPacket)
        end)
    end
    bindRemoteEvent(RELIABLE_EVENT)
    bindRemoteEvent(UNRELIABLE_EVENT)

    RunService.Heartbeat:Connect(function(_dt)
        local reliable, unreliable = PacketParser.ProcessOut(OutgoingPackets:flush())
        if reliable then
            RELIABLE_EVENT:FireServer(reliable)
        end
        if unreliable then
            UNRELIABLE_EVENT:FireServer(unreliable)
        end
    end)
end

function RemoteAPI:Connect(boundFn: (...any) -> ()): () -> ()
    local cursor = #self._listeners+1
    self._listeners[cursor] = boundFn
    return function()
        return table.remove(self._listeners, cursor)
    end
end

function RemoteAPI:DisconnectAtCursor(cursor: number?)
    local size = #self._listeners
    if size > 0 then
        local currentListener = self._listeners[cursor or size]
        if not currentListener then
            error("No bound connections are found")
        end
        table.remove(self._listeners, currentListener)
    end
end

function RemoteAPI:DisconnectAll()
    table.clear(self._listeners)
end

function RemoteAPI:Destroy()
    RunningRemotes[self._id] = nil
    table.clear(self._listeners)
    self._listeners = nil
    setmetatable(self, nil)
end

local Remote = {}
Remote.__index = RemoteAPI
Remote.__metatable = "The metatable is locked"
Remote.__tostring = function(self)
    return self.Name
end
function Remote.new(remoteName: string, unreliable: boolean?)
    local self = {}
    self.Name = remoteName
    self._type = if unreliable then '.U' else '.R'
    self._id = Hash.sha256(remoteName .. self._type)
    self._unreliable = unreliable
    self._listeners = {}
    setmetatable(self, Remote)
    RunningRemotes[self._id] = self
    return self
end

return {
    new = Remote.new,
}