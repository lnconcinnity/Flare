local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Buffer = require(script.Parent.buffer)
local PacketChannel = require(script.Parent.Parent.util.Channel)
local Set = require(script.Parent.Parent.util.Set)

type TargetPlayer = Player | {Player}
type DataType =  "CFrame" | "Vector3" | "Vector2" | "Vector2int16" | "Vector3int16" | "DateTime" | "Color3" | "BrickColor" | "Ray" | "Rect" | "Region3" | "UDim" | "UDim2" | "u8" | "u16" | "u32" | "i8" | "i16" | "i32" | "f32" | "f64" | "string" | "boolean"
export type Packet = {
    KeysSet: {[string]: boolean},
    TypeMap: {[string]: DataType},
    DefaultsMap: {[string]: any},
    PacketSize: number,
}
export type OutgoingPacket = {[string]: any}
export type PacketData = {
    Player: Player?,
    Ping: {
        Downtime: number,
        Uptime: number,
    }
}
type Receiver = {
    Packet: Packet,
    Name: string,
    IsReliable: boolean,
    IsDynamic: boolean,
    IsRequester: boolean,
    Subscriptions: {(data: PacketData) -> ()},
    Request: (data: PacketData) -> (),
    RequestThreadsList: {string},
}
export type PacketDefinition = {[string]: {type: DataType, default: any?}}
export type ReceiverDefinition = {
    Name: string,
    IsReliable: boolean,
    IsDynamic: boolean,
    IsRequester: boolean,
    Packet: Packet,
}

local IS_SERVER = RunService:IsServer()
local NUMBERICALS = Set("u8", "u16", "u32", "i8", "i16", "i32", "f32", "f64")
local INDEFINITE_TYPES = Set("map", "array", "boolean", "Instance", "Enum", "string")

local UnreliableBridgeEvent,  ReliableBridgeEvent = script.Parent:WaitForChild("UnreliableBridge"), script.Parent:WaitForChild("ReliableBridge")
local OutgoingPacketsStream = {Outbound = PacketChannel.new()}
local DefinitionsInitialized = false
local CurrentClockTime = workspace:GetServerTimeNow()
local Receivers = {}
local RequesterThreads = {}

local function IsDataTypeNumber(type: string): boolean
    return NUMBERICALS[type] ~= nil
end

local function ProcessOutgoingPackets(outgoingPackets: {{TargetReceiver: string, Reliable: boolean, Dynamic: boolean, Requesting: boolean, RequesterId: string?, RequestStatus: number?, Packet: Packet, Data: OutgoingPacket}}): (any?, any?)
    local outgoingPacketCount = #outgoingPackets
    if outgoingPacketCount > 0 then
        local unreliable, reliable = {}, {}
        for i = 1, outgoingPacketCount do
            local outgoingPacket = outgoingPackets[i]
            local data = outgoingPacket.Data or {}
            local size = if outgoingPacket.Packet then outgoingPacket.Packet.PacketSize else 0
            local writer = Buffer.write(size+10) -- strings self-allocate
            writer:writebool(outgoingPacket.Requesting or false)
            writer:writeu8(outgoingPacket.RequestStatus or 0)
            writer:writestring(outgoingPacket.TargetReceiver)
            writer:writestring(outgoingPacket.RequesterId or '')
            writer:writef64(CurrentClockTime)
            -- if we are going dynamic, dynamic packets are much more expensive to iterate
            if outgoingPacket.Dynamic then
                local keys, types, values = {}, {}, {}
                local count, typeSize = 0, 0
                for key, value in data do
                    count += 1
                    keys[#keys+1] = key
                    local type = typeof(value)
                    if type == "number" then
                        local cast, sizecast = Buffer.datatypes.AssumeNumberSize(value)
                        type = cast..sizecast
                    elseif type == "boolean" then
                        type = "bool"
                    elseif type == "table" then
                        type = if value[1] ~= nil then 'array' else 'map'
                        local _, keyTypes = Buffer.datatypes.WriteDynamicOutput(value, 1) do
                            for q = 1, #keyTypes do
                                local datatype = Buffer.datatypes.ReadWrite[keyTypes[q]]
                                if datatype then
                                    typeSize += datatype.size
                                end
                            end
                        end
                        local _, valueTypes = Buffer.datatypes.WriteDynamicOutput(value, 2) do
                            for q = 1, #valueTypes do
                                local datatype = Buffer.datatypes.ReadWrite[valueTypes[q]]
                                if datatype then
                                    typeSize += datatype.size
                                end
                            end
                        end
                    elseif type == "Instance" then
                        type = 'instance'
                    elseif type == "EnumItem" then
                        type = 'enum'
                    elseif type ~= "string" then
                        type = type..'$'
                    end
                    types[#types+1] = type
                    values[#values+1] = value
                    local datatype = Buffer.datatypes.ReadWrite[type]
                    if datatype then
                        typeSize += datatype.size
                    end
                end
                writer:writeu32(typeSize)
                writer:writeu16(count)
                if count > 0 then
                    for j = 1, count do
                        -- key type, value
                        writer:writestring(keys[j])
                        local type = types[j]
                        local isRobloxType = type:sub(#type) == '$'
                        local robloxType = type:sub(1, #type-1)
                        writer:writestring(type)
                        if isRobloxType then
                            writer:writetype(robloxType, values[j])
                        else
                            writer[`write{type}`](writer, values[j])
                        end
                    end
                end
            else
                writer:writeu32(size)
                for key in pairs(outgoingPacket.Packet.KeysSet) do
                    local value = data[key] or outgoingPacket.Packet.DefaultsMap[key]
                    local type = typeof(value)
                    local curType = outgoingPacket.Packet.TypeMap[key]
                    if type == "table" then
                        type = if next(value) == nil then curType elseif value[1] ~= nil then 'array' else 'map'
                    elseif type == "EnumItem" then
                        type = 'Enum'
                    end
                    if (type ~= "number" and type ~= curType) or (IsDataTypeNumber(curType) and type ~= "number") then
                        error("invalid write allocation, got "..type.." opposed to "..outgoingPacket.Packet.TypeMap[key])
                    end
                    if type == "string" then
                        writer:writestring(value)
                    elseif type == "boolean" then
                        writer:writebool(value)
                    elseif type == "number" then
                        writer[`write{outgoingPacket.Packet.TypeMap[key]}`](writer, value)
                    elseif type == 'Instance' then
                        writer:writeinstance(value)
                    elseif type == "map" then
                        writer:writemap(value)
                    elseif type == "array" then
                        writer:writearray(value)
                    elseif type == "Enum" then
                        writer:writeenum(value)
                    else
                        writer:writetype(type, value)
                    end
                end
            end
            local buff = writer:getbuffer()
            if outgoingPacket.Reliable or outgoingPacket.Requesting then -- requesters are forced to be reliable
                reliable[#reliable+1] = buff
            else
                unreliable[#unreliable+1] = buff
            end
        end
        return Buffer.merge(unreliable), Buffer.merge(reliable)
    end
    return nil, nil
end

local function _internalProcessIncomingPackets(reader: any, data: typeof({}), packetDef: Packet, fromDynamic: boolean): PacketData
    if fromDynamic then
        local allocCount = reader:readu16()
        if allocCount > 0 then
            for _ = 1, allocCount do
                local key = reader:readstring()
                local type = reader:readstring()
                local robloxType = type:sub(1, #type-1)
                local value = nil
                local isRobloxType = type:sub(#type) == '$'
                if isRobloxType then
                    value = reader:readtype(robloxType)
                else
                    value = reader[`read{type}`](reader)
                end
                data[key] = value
            end
        end
    else
        for key in pairs(packetDef.KeysSet) do
            local out = nil
            local type = packetDef.TypeMap[key]
            local isNumber = IsDataTypeNumber(type)
            if isNumber then
                out = reader[`read{type}`](reader)
            elseif type == "string" then
                out = reader:readstring()
            elseif type == "map" then
                out = reader:readmap()
            elseif type == "array" then
                out = reader:readarray()
            elseif type == "boolean" then
                out = reader:readbool()
            elseif type == "Instance" then
                out = reader:readinstance()
            elseif type == "Enum" then
                out = reader:readenum()
            else
                out = reader:readtype(type)
            end
            data[key] = out
        end
    end
end

local function ProcessIncomingPackets(buff: any, player: Player?)
---@diagnostic disable-next-line: undefined-global
    local len = buffer.len(buff)
    local reader = Buffer.read(buff)
    while reader.Cursor < len do
        local requesting = reader:readbool()
        local requestStatus = reader:readu8()
        local receiverName = reader:readstring()
        local requesterId = reader:readstring()
        local localtime = reader:readf64()
        local totalPacketSize = reader:readu32()
        local receiver = Receivers[receiverName]--receivers will always exist
        if not receiver then
            break
        else
            local timestamp = (CurrentClockTime / localtime) - 1
            local uptime = (1-timestamp)*100
            local data = {}
            data.Player = player
            data.Ping = {
                Uptime = uptime,
                Downtime = (100 - uptime),
            }
            local packetDef = receiver.Packet
            _internalProcessIncomingPackets(reader, data, packetDef, receiver.IsDynamic or requestStatus ~= 0) -- force evaluate dynamically if request ok
            if requesting then
                if requestStatus == 0 then
                    -- case 1, unevaluated
                    task.spawn(function()
                        -- Request expects a table in key-value pairs
                        local success, out = xpcall(receiver.Request, warn, data)
                        local status = if success then 1 else 2
                        if type(out) == "string" then
                            out = {Error = out}
                        end
                        local packet = {TargetReceiver = receiverName, Requesting = true, RequesterId = requesterId, RequestStatus = status, Dynamic = true, Packet = receiver.Packet, Data = out} -- force evaluate dynamically
                        if IS_SERVER then
                            OutgoingPacketsStream.Players[player]:Dump(packet)
                        else
                            OutgoingPacketsStream.Outbound:Dump(packet)
                        end
                    end)
                else
                    local requester = RequesterThreads[requesterId]
                    if not requester then
                        warn(`requester thread "{requesterId}" has been terminated, dropping packets of said request`)
                        reader.Cursor += totalPacketSize
                    end
                    RequesterThreads[requesterId] = nil
                    if requestStatus == 1 then
                    task.spawn(requester, data)
                    elseif requesting == 2 then
                        task.cancel(requester)
                        warn("packet dropped due to back-end errors\nparsed error:\n"..data.Error)
                    end
                end
            else
                for _, subscriber: (data: PacketData) -> () in receiver.Subscriptions do
                    task.spawn(subscriber, data)
                end
            end
        end
    end
end

local Packet = {}
function Packet.subscribeTo(receiverName: string, bound: (data: PacketData) -> ()): (() -> ())
    local receiver = Receivers[receiverName]
    assert(receiver ~= nil, `no receiver definition for unknown receiver "{receiverName}"`)
    if receiver.IsRequester then
        receiver.Request = bound
    else
        local at = #receiver.Subscriptions+1
        receiver.Subscriptions[at] = bound
        return function()
            if receiver.Subscriptions then
                table.remove(receiver.Subscriptions, at)
            end
        end
    end
end

if IS_SERVER then
    OutgoingPacketsStream.Players = {}
    function Packet.publishAtTargets(target: TargetPlayer, toReceiver: string, data: OutgoingPacket)
        assert((typeof(target) == "Instance" and target:IsA("Player")) or (type(target) == "table" and #target > 0 and typeof(target[1]) == "Instance" and target[1]:IsA("Player")), "Argument 1 expects a player or an array of players")
        local receiver = Receivers[toReceiver]
        if not receiver then
            error(`receiver "{toReceiver}" does not exist`)
        end
        if type(target) == "table" then
            for _, player in target do
                OutgoingPacketsStream.Players[player]:Dump({TargetReceiver = toReceiver, Reliable = receiver.IsReliable, Dynamic = receiver.IsDynamic, Packet = receiver.Packet, Data = data})
            end
        else
            OutgoingPacketsStream.Players[target]:Dump({TargetReceiver = toReceiver, Reliable = receiver.IsReliable, Dynamic = receiver.IsDynamic, Packet = receiver.Packet, Data = data})
        end
    end
    function Packet.publishAtGlobal(toReceiver: string, data: OutgoingPacket)
        local receiver = Receivers[toReceiver]
        if not receiver then
            error(`receiver "{toReceiver}" does not exist`)
        end
        OutgoingPacketsStream.Outbound:Dump({TargetReceiver = toReceiver, Reliable = receiver.IsReliable, Dynamic = receiver.IsDynamic, Packet = receiver.Packet, Data = data})
    end
    function Packet.pubishWithExemptions(except: TargetPlayer, toReceiver: string, data: OutgoingPacket)
        assert((typeof(except) == "Instance" and except:IsA("Player")) or (type(except) == "table" and #except > 0 and typeof(except[1]) == "Instance" and except[1]:IsA("Player")), "Argument 1 expects a player or an array of players")
        local receiver = Receivers[toReceiver]
        if not receiver then
            error(`receiver "{toReceiver}" does not exist`)
        end
        if type(except) == "table" then
            local setAs = Set(table.unpack(except))
            for _, player in Players:GetPlayers() do
                if setAs[player] then continue end
                OutgoingPacketsStream.Players[player]:Dump({TargetReceiver = toReceiver, Reliable = receiver.IsReliable, Dynamic = receiver.IsDynamic, Packet = receiver.Packet, Data = data})
            end
        else
            for _, player in Players:GetPlayers() do
                if player == except then continue end
                OutgoingPacketsStream.Players[player]:Dump({TargetReceiver = toReceiver, Reliable = receiver.IsReliable, Dynamic = receiver.IsDynamic, Packet = receiver.Packet, Data = data})
            end
        end
    end

    local function bindRemoteEvent(event: RemoteEvent | UnreliableRemoteEvent)
        event.OnServerEvent:Connect(function(player: Player, receivedBuffer: any)
            ProcessIncomingPackets(receivedBuffer, player)
        end)
    end
    local function onPlayerAdded(player: Player)
        OutgoingPacketsStream.Players[player] = PacketChannel.new()
    end
    Players.PlayerAdded:Connect(onPlayerAdded)
    for _, player in Players:GetPlayers() do
        task.spawn(onPlayerAdded, player)
    end
    Players.PlayerRemoving:Connect(function(player: Player)
        if OutgoingPacketsStream.Players[player] then
            OutgoingPacketsStream.Players[player]:Destroy()
        end
        OutgoingPacketsStream.Players[player] = nil
    end)
    bindRemoteEvent(ReliableBridgeEvent)
    bindRemoteEvent(UnreliableBridgeEvent)
    RunService.Heartbeat:Connect(function(_)
        CurrentClockTime = workspace:GetServerTimeNow()
        local globalUnreliable, globalReliable = ProcessOutgoingPackets(OutgoingPacketsStream.Outbound:Flush())
        for player, channel in pairs(OutgoingPacketsStream.Players) do
            local _unreliable, _reliable = ProcessOutgoingPackets(channel:Flush())
            local unreliable, reliable
            if globalReliable and not _reliable then
                reliable = globalReliable
            else
                reliable = Buffer.merge({_reliable, globalReliable})
            end
            if globalUnreliable and not _unreliable then
                unreliable = globalUnreliable
            else
                unreliable = Buffer.merge({_unreliable, globalUnreliable})
            end
            
            if reliable then
                ReliableBridgeEvent:FireClient(player, reliable)
            end
            if unreliable then
                UnreliableBridgeEvent:FireClient(player, unreliable)
            end
        end
    end)
else
    function Packet.publishData(toReceiver: string, data: OutgoingPacket)
        local receiver = Receivers[toReceiver]
        if not receiver then
            error(`receiver "{toReceiver}" does not exist`)
        end
        OutgoingPacketsStream.Outbound:Dump({TargetReceiver = toReceiver, Reliable = receiver.IsReliable, Dynamic = receiver.IsDynamic, Packet = receiver.Packet, Data = data})
    end
    function Packet.request(toReceiver: string, data: OutgoingPacket)
        local receiver = Receivers[toReceiver]
        if not receiver then
            error(`receiver "{toReceiver}" does not exist`)
        end
        local id = HttpService:GenerateGUID(false)
        local thread = coroutine.running()
        RequesterThreads[id] = thread
        receiver.RequestThreadsList[thread] = true
        OutgoingPacketsStream.Outbound:Dump({TargetReceiver = toReceiver, Requesting = true, RequesterId = id, RequestStatus = 0, Dynamic = receiver.IsDynamic, Packet = receiver.Packet, Data = data})
        return coroutine.yield()
    end
    local function bindRemoteEvent(event: RemoteEvent | UnreliableRemoteEvent)
        event.OnClientEvent:Connect(function(receivedBuffer: any)
            ProcessIncomingPackets(receivedBuffer)
        end)
    end
    bindRemoteEvent(ReliableBridgeEvent)
    bindRemoteEvent(UnreliableBridgeEvent)
    RunService.Heartbeat:Connect(function(_)
        CurrentClockTime = workspace:GetServerTimeNow()
        local unreliable, reliable = ProcessOutgoingPackets(OutgoingPacketsStream.Outbound:Flush())
        if reliable then
            ReliableBridgeEvent:FireServer(reliable)
        end
        if unreliable then
            UnreliableBridgeEvent:FireServer(unreliable)
        end
    end)
end

function Packet.definePacket(definition: PacketDefinition): Packet
    local packet = {
        PacketSize = 0,
        KeysSet = {},
        TypeMap = {},
        DefaultsMap = {},
    }
    local structureSize = 0
    for key, datatype in definition do
        assert(type(datatype) == "table", "expected key-value pairs")
        if datatype.type ~= "Instance" then
            assert(datatype.default ~= nil, "cannot have an empty as default value")
        else
            if datatype.default == nil then
                datatype.default = game
            end
        end
        packet.KeysSet[key] = true
        packet.TypeMap[key] = datatype.type
        packet.DefaultsMap[key] = datatype.default
        if typeof(datatype.default) == "Instance" then
            datatype.default = datatype.default:GetFullName()
        end
        if (type(datatype.default) == "number" or IsDataTypeNumber(datatype.type)) or INDEFINITE_TYPES[datatype.type] then continue end -- strings are indeterminate, numbers vary, instances are passed as a hierarchy, bools are represented by 1s and 0s
        local data = Buffer.datatypes.ReadWrite[datatype.type]
        assert(data ~= nil, `unsupported datatype, got "{datatype.type}"`)
        structureSize += data.size
    end
    packet.PacketSize = structureSize
    return packet
end

function Packet.listreceivers(): {string}
    local receivers = {}
    for key in Receivers do
        receivers[#receivers+1] = key
    end
    return table.concat(receivers, ", ")
end

function Packet.load()
    if DefinitionsInitialized then
        error("Packets are already initialized")
    end
    local PacketInitializer = ReplicatedStorage:FindFirstChild("PacketInitializer", true)
    if PacketInitializer and PacketInitializer:IsA("ModuleScript") then
        local ok, loader = xpcall(require, warn, PacketInitializer)
        if ok then
            assert(type(loader) == "function", "expected a function to initialize")
            loader(Packet.definePacket, Packet.defineReceiver, Packet.listreceivers, Packet.disbandReceiver)
        end
        DefinitionsInitialized = true
    end
    return Packet
end

function Packet.disbandReceiver(receiverName: string)
    local receiver = Receivers[receiverName]
    assert(receiver ~= nil, `attempt to disband unknown receiver, tried "{receiverName}"`)
    for id in receiver.RequestThreadsList do
        task.cancel(RequesterThreads[id])
        RequesterThreads[id] = nil
    end
    table.clear(receiver.Subscriptions)
    Receivers[receiverName] = nil
end

function Packet.defineReceiver(receiverDefinition: ReceiverDefinition)
    local name = receiverDefinition.Name
    assert(#name > 0, "cannot have an empty-string for receiver name")
    local receiver: Receiver = {}
    receiver.IsRequester = receiverDefinition.IsRequester
    receiver.IsReliable = if receiverDefinition.IsRequester then true else receiverDefinition.IsReliable
    receiver.IsDynamic = receiverDefinition.IsDynamic
    receiver.Name = name
    receiver.Subscriptions = {}
    receiver.RequestThreadsList = {}
    receiver.Request = nil
    receiver.Packet = receiverDefinition.Packet
    Receivers[name] = receiver
    return receiver
end

local ExportedPacket = {
    DefineReceiver = Packet.defineReceiver,
    DefinePacket = Packet.definePacket,
    Disband = Packet.disbandReceiver,
    List = Packet.listreceivers,
    Subscribe = Packet.subscribeTo,
}

if IS_SERVER then
    ExportedPacket.PublishClient = Packet.publishAtTargets
    ExportedPacket.PublishAllClients = Packet.publishAtGlobal
    ExportedPacket.PublishWithExceptions = Packet.pubishWithExemptions
else
    ExportedPacket.Request = Packet.request
    ExportedPacket.Publish = Packet.publishData
end

Packet.load()
return ExportedPacket