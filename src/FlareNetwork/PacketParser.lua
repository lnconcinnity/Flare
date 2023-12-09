local BufferWriter = require(script.Parent.BufferWriter)

local TYPES_SEPARATOR = "/"

local PacketParser = {}
function PacketParser.ProcessOut(unprocessedPackets, player: Player?): (any, any)
    if unprocessedPackets ~= nil then
        local unprocessedPacketCount = #unprocessedPackets
        if unprocessedPacketCount > 0 then
            local processedReliable = {}
            local processedUnreliable = {}
            for i = 1, unprocessedPacketCount do
                local packet = unprocessedPackets[i]
                local bufferSize = (#packet.target+1)+(#packet.debugName+1)
                local types: {string} = {}
                local argCount = #packet.args
                for j = 1, argCount do
                    local value = packet.args[j]
                    local type = typeof(value)
                    local size, fintOrStringLength = BufferWriter.GetValueByteSize(value)
                    if type == "number" then
                        type = type..fintOrStringLength..size
                    end
                    types[#types+1] = type
                    bufferSize += size
                end
                types = table.concat(types, TYPES_SEPARATOR)
                bufferSize += #types+1
                local buff = buffer.create(bufferSize)
                local bufferCursor = 0
                bufferCursor += BufferWriter.Write(buff, bufferCursor, packet.target)
                bufferCursor += BufferWriter.Write(buff, bufferCursor, packet.debugName)
                bufferCursor += BufferWriter.Write(buff, bufferCursor, types)
                for j = 1, argCount do
                    local value = packet.args[j]
                    bufferCursor += BufferWriter.Write(buff, bufferCursor, value) or 0
                end
                local target = if packet.unreliable then processedUnreliable else processedReliable
                target[#target+1] = buff
            end
            return BufferWriter.Merge(processedReliable), BufferWriter.Merge(processedUnreliable), player
        end
    end
    return nil, nil, player
end

function PacketParser.ProcessIn(recievedBuffer: any, onProcessed: (...any) -> (), recipient: Player?): ({target: string, debugName: string, recipient: Player?, args: {any}})
    local bufferLen = buffer.len(recievedBuffer)
    local bufferCursor = 0
    while bufferCursor < bufferLen do
        local targetName: string, targetNameLength: number = BufferWriter.Read(recievedBuffer, bufferCursor, "string")
        bufferCursor+=targetNameLength
        local debugName: string, debugNameLength: number = BufferWriter.Read(recievedBuffer, bufferCursor, "string")
        bufferCursor+= debugNameLength
        local types: string, typesLength: number = BufferWriter.Read(recievedBuffer, bufferCursor, "string")
        bufferCursor+= typesLength
        types = string.split(types, TYPES_SEPARATOR)
        local args = {}
        for j = 1, #types do
            local size: number = nil
            args[#args+1], size = BufferWriter.Read(recievedBuffer, bufferCursor, types[j])
            bufferCursor += size
        end
        onProcessed({target = targetName, debugName = debugName, recipient = recipient, args = args})
    end
end

return PacketParser