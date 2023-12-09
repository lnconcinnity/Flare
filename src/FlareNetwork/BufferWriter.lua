-- PacketParser.lua, BufferWriter.lua, Channel.lua and Remote.lua were originally of ffrostfall's ByteNet networking system; repurposed for my own uses

local BYTE_SIZES = {
    Vector3 = 12,
    CFrame = 48, -- pos, qX, qY, qZ
    float32 = 32,
    float64 = 64,
    int8 = 8,
    int16 = 16,
    int32 = 32,
    boolean = 1,
}

local function getValueByteSize(value: any): (number, string?)
    local type = typeof(value)
    if type == "Vector3" then
        return BYTE_SIZES.Vector3
    elseif type == "CFrame" then
        return BYTE_SIZES.CFrame
    elseif type == "number" then
        local isFloat = select(2, math.modf(value)) > 0
        local size = #tostring(value)
        if isFloat then
            return if size > 32 then BYTE_SIZES.float64 else BYTE_SIZES.float32, 'f'
        else
            return if size < 8 then BYTE_SIZES.int8 elseif size < 16 then BYTE_SIZES.int16 else BYTE_SIZES.int32, 'i'
        end
    elseif type == "string" then -- a string is indeterminate
        local len = #value
        return len+1, len
    elseif type == "boolean" then
        return BYTE_SIZES.boolean
    end
end

local BufferWriter = {
    Sizes = BYTE_SIZES,
    GetValueByteSize = getValueByteSize
}
function BufferWriter.Merge(buffers: {any}): any
    local totalSize = 0
    local mergeCount = #buffers
    if mergeCount == 0 then return nil end
    for k = 1, mergeCount do
        totalSize += buffer.len(buffers[k])
    end

    local mergedBuffer = buffer.create(totalSize)
    local bufferCursor = 0
    for k = 1, mergeCount do
        local currentBuffer = buffers[k]
        buffer.copy(mergedBuffer, bufferCursor, currentBuffer)
        bufferCursor += buffer.len(currentBuffer)
    end
    return mergedBuffer
end


function BufferWriter.Write(targetBuffer: any, offset: number, value: any): number
    local type = typeof(value)
    local size, fintOrStringLength = getValueByteSize(value)
    if type == "Vector3" then
        buffer.writef32(targetBuffer, offset, value.X)
        buffer.writef32(targetBuffer, offset+4, value.Y)
        buffer.writef32(targetBuffer, offset+8, value.Z)
    elseif type == "CFrame" then
        buffer.writef32(targetBuffer, offset, value.Position.X) -- x
        buffer.writef32(targetBuffer, offset+4, value.Position.Y) -- y
        buffer.writef32(targetBuffer, offset+8, value.Position.Z) -- z
        buffer.writef32(targetBuffer, offset+12, -value.LookVector.X) -- -lx
        buffer.writef32(targetBuffer, offset+16, -value.LookVector.Y) -- -ly
        buffer.writef32(targetBuffer, offset+20, -value.LookVector.Z) -- -lz
        buffer.writef32(targetBuffer, offset+24, value.RightVector.X) -- rx
        buffer.writef32(targetBuffer, offset+28, value.RightVector.Y) -- ry
        buffer.writef32(targetBuffer, offset+32, value.RightVector.Z) -- rz
        buffer.writef32(targetBuffer, offset+36, value.UpVector.X) -- ux
        buffer.writef32(targetBuffer, offset+40, value.UpVector.Y) -- uy
        buffer.writef32(targetBuffer, offset+44, value.UpVector.Z) -- uz
    elseif type == "number" then
        local format = fintOrStringLength..size
        buffer[`write{format}`](targetBuffer, offset, value)
        return size, format
    elseif type == "boolean" then
        buffer.writeu8(targetBuffer, offset, if value == true then 1 else 0)
    elseif type == "string" then
        buffer.writeu8(targetBuffer, offset, fintOrStringLength)
        buffer.writestring(targetBuffer, offset + 1, value)
    end
    return size
end

function BufferWriter.Read(targetBuffer: any, offset: number, type: string): any
    if type == "Vector3" then
        return Vector3.new(
            buffer.readf32(targetBuffer, offset),
            buffer.readf32(targetBuffer, offset+4),
            buffer.readf32(targetBuffer, offset+8)
        ), BYTE_SIZES.Vector3
    elseif type == "CFrame" then
        local position = BufferWriter.Read(targetBuffer, offset, "Vector3")
        local lookVector = BufferWriter.Read(targetBuffer, offset+12, "Vector3")
        local rightVector = BufferWriter.Read(targetBuffer, offset+24, "Vector3")
        local upVector = BufferWriter.Read(targetBuffer, offset+36, "Vector3")
        return CFrame.fromMatrix(position, rightVector, upVector, lookVector), BYTE_SIZES.CFrame
    elseif type:sub(1,6) == "number" then
        local format = type:sub(7)
        return assert(buffer[`read{format}`], "Passed an invalid reading format for a number.")(targetBuffer, offset), tonumber(format:sub(2))
    elseif type == "boolean" then
        return buffer.readu8(targetBuffer, offset) == 1, BYTE_SIZES.boolean
    elseif type == "string" then
        local len = buffer.readu8(targetBuffer, offset)
		return buffer.readstring(targetBuffer, offset + 1, len), len+1
    end
end

return BufferWriter