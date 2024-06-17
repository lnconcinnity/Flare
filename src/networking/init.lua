local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Packet = require(script.Packet)
local blueSerializer = require(script.Parent.private.blueSerializer)

export type FlareRemotePacketData = Packet.PacketData
export type FlareRemote = {
    Name: string,
    Fire: (self: FlareRemote, player: {Player} | Player, data: Packet.OutgoingPacket) -> (),
    FireAll: (self: FlareRemote, data: Packet.OutgoingPacket) -> (),
    FireExcept: (self: FlareRemote, except: {Player} | Player, data: Packet.OutgoingPacket) -> (),

    Fire: (self: FlareRemote, data: Packet.OutgoingPacket) -> (),
    Invoke: (self: FlareRemote, data: Packet.OutgoingPacket) -> (Packet.PacketData),

    Connect: (self: FlareRemote, bound: (data: Packet.PacketData) -> ()) -> (),
}

local IS_SERVER = RunService:IsServer()

local FlareRemoteMetatable = {}
FlareRemoteMetatable.__index = FlareRemoteMetatable
if IS_SERVER then
    function FlareRemoteMetatable:Fire(player: {Player} | Player, data: Packet.OutgoingPacket)
        Packet.PublishClient(player, self.Name, data)
    end
    function FlareRemoteMetatable:FireAll(data: Packet.OutgoingPacket)
        Packet.PublishAllClients(self.Name, data)
    end
    function FlareRemoteMetatable:FireExcept(except: {Player} | Player, data: Packet.OutgoingPacket)
        Packet.PublishWithExceptions(except, self.Name, data)
    end
else
    function FlareRemoteMetatable:Fire(data: Packet.OutgoingPacket)
        Packet.Publish(self.Name, data)
    end
    function FlareRemoteMetatable:Invoke(data: Packet.OutgoingPacket): (Packet.PacketData)
        return Packet.Request(self.Name, data)
    end
end
function FlareRemoteMetatable:Connect(bound: (data: Packet.PacketData) -> ())
    return Packet.Subscribe(self.Name, bound)
end
local FlareRemote = {} -- mimic remote events, remote functions will be overshadowed by a remotevent
function FlareRemote.new(remoteName: string, reliable: boolean, requester: boolean, packet: Packet.Packet?): FlareRemote
    local self = {}
    self.Name = remoteName
    Packet.DefineReceiver({
        Name =  remoteName,
        IsDynamic = not packet, -- force remotes to be dynamic (chuu~~)
        IsReliable = reliable,
        IsRequester = requester,
        Packet = packet,
    })
    setmetatable(self, FlareRemoteMetatable)
    return self
end

local FlareNetworkMetatable = {}
FlareNetworkMetatable.__index = FlareNetworkMetatable
if IS_SERVER then
    function FlareNetworkMetatable:MakeRemote(remoteName: string, isReliable: boolean?, isRequester: boolean?, packetDefinition: {[string]: {default: string, type: string, packetOrder: number?}}?): (() -> ())
        isReliable = if isReliable ~= nil then isReliable else true
        isRequester = if isRequester ~= nil then isRequester else false
        local receiverName = `{self.NetworkName}<{remoteName}>` -- we want networks to be exclusive to each other
        local packet, packetStream = nil, {}
        if packetDefinition then
            packet = Packet.DefinePacket(packetDefinition)
            for name, data in pairs(packetDefinition) do
                if data.type == "Instance" and data.default == nil then
                    data.default = game
                elseif data.default == nil then
                    error("required default data")
                end
                local ser = HttpService:JSONEncode(blueSerializer.serialize(data.default))
                packetStream[#packetStream+1]= {stream = `{name}\0{data.type}\0{ser}`, order = data.packetOrder or tick()}
            end
            table.sort(packetStream, function(a, b)
                return a.order < b.order
            end)
            for i = #packetStream, 1, -1 do
                packetStream[i] = packetStream[i].stream
            end
        end
        local remote = FlareRemote.new(receiverName, isReliable, isRequester, packet)
        self[remoteName] = remote
        self.NetworkContainer:SetAttribute(remoteName, `{if isReliable then 'a' else 'b'}{if isRequester then 'a' else 'b'}{if packetDefinition ~= nil then 'a' else 'b'}`..table.concat(packetStream,'/'))
        return function()
            self[remoteName] = nil
            self.NetworkContainer:SetAttribute(remoteName, nil)
            Packet.Disband(receiverName)
        end
    end
else
    function FlareNetworkMetatable:Build()
        local remotes = {}
        local function onAttributeAdded(attributeName: string, attributeValue: string)
            local receiverName = `{self.NetworkName}<{attributeName}>`
            local reliable, requester, defined = attributeValue:sub(1, 1) == 'a', attributeValue:sub(2, 2) == 'a', attributeValue:sub(3, 3) == 'a'
            local packet
            if defined then
                local stream = {}
                local content = string.split(attributeValue:sub(4), '/')
                for _, packetStream in ipairs(content) do
                    local keys = packetStream:split('\0')
                    local out = HttpService:JSONDecode(keys[3])
                    stream[keys[1]] = {type = keys[2], default = if type(out) == "boolean" then out else tonumber(keys[3]) or blueSerializer.deserialize(out)}
                end
                packet = Packet.DefinePacket(stream)
            end
            local remote = FlareRemote.new(receiverName, reliable, requester, packet)
            self[attributeName] = remote
            remotes[attributeName] = receiverName
        end
        for attributeName, attributeValue in self.NetworkContainer:GetAttributes() do
            task.spawn(onAttributeAdded, attributeName, attributeValue)
        end
        self.NetworkContainer.AttributeChanged:Connect(function(attributeName)
            local attributeValue = self.NetworkContainer:GetAttribute(attributeName)
            if attributeValue ~= nil and remotes[attributeName] == nil then
                onAttributeAdded(attributeName, attributeValue)
            else
                if remotes[attributeName] then
                    Packet.Disband(remotes[attributeName])
                end
                self[attributeName] = nil
            end
        end)
    end
end

local FlareNetwork = {Packet = Packet,}
function FlareNetwork.new(networkName: string)
    local self = {}
    self.NetworkName = networkName
    self.NetworkContainer = if IS_SERVER then Instance.new("Configuration") else script:WaitForChild(networkName)
    self.NetworkContainer.Name = networkName
    self.NetworkContainer.Parent = script
    setmetatable(self, FlareNetworkMetatable)
    return self
end

return FlareNetwork