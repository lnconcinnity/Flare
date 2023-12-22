-- PacketParser.lua, BufferWriter.lua, Channel.lua and Remote.lua were originally of ffrostfall's ByteNet networking system; repurposed for my own uses

local BYTE_SIZES = {
    DateTime = 8,
    UDim = 8,
    UDim2 = 16,
    BrickColor = 2,
    Ray = 24,
    Region3 = 24,
    Vector3int16 = 6,
    Vector2int16 = 2,
    Region3int16 = 12,
    Rect = 24,
    Color3 = 12,
    Vector2 = 8,
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
    if type == "number" then
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
    elseif type == "Instance" then
        error("Cannot pass an Instance due to the inability to viably index said instance all-throughout the game. (Roblox limitation)")
    else
        return assert(BYTE_SIZES[type], `{type} is not a supported value for buffer writing`)
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
    elseif type == "Vector2" then
        buffer.writef32(targetBuffer, offset, value.X)
        buffer.writef32(targetBuffer, offset+4, value.X)
    elseif type == "CFrame" then
        BufferWriter.Write(targetBuffer, offset, value.Position)
        BufferWriter.Write(targetBuffer, offset+12, value.ZVector)
        BufferWriter.Write(targetBuffer, offset+24, value.XVector)
        BufferWriter.Write(targetBuffer, offset+36, value.YVector)
    elseif type == "Color3" then
        buffer.writef32(targetBuffer, offset, value.R)
        buffer.writef32(targetBuffer, offset+4, value.G)
        buffer.writef32(targetBuffer, offset+8, value.B)
    elseif type == "BrickColor" then
        buffer.writei16(targetBuffer, offset, value.Number)
    elseif type == "DateTime" then
        buffer.writef64(targetBuffer, offset, value.UnixTimestampMillis)
    elseif type == "Ray" then
        BufferWriter.Write(targetBuffer, offset, value.Origin)
        BufferWriter.Write(targetBuffer, offset+12, value.Direction)
    elseif type == "Rect" then
        BufferWriter.Write(targetBuffer, offset, value.Min)
        BufferWriter.Write(targetBuffer, offset+12, value.Max)
    elseif type == "Region3" then
		local center = value.CFrame.Position
		local sizeHalf = value.Size * 0.5
		local min = center - sizeHalf
		local max = center + sizeHalf
		BufferWriter.Write(targetBuffer, offset, min)
		BufferWriter.Write(targetBuffer, offset+12, max)
    elseif type == "UDim" then
		buffer.writef32(targetBuffer, offset, value.Scale)
		buffer.writei32(targetBuffer, offset+4, value.Offset)
    elseif type == "UDim2" then
        BufferWriter.Write(targetBuffer, offset, value.X)
        BufferWriter.Write(targetBuffer, offset+8, value.Y)
    elseif type == "Vector3int16" then
        buffer.writei16(targetBuffer, offset, value.X)
        buffer.writei16(targetBuffer, offset+2, value.Y)
        buffer.writei16(targetBuffer, offset+4, value.Z)
    elseif type == "Vector2int16" then
        buffer.writei16(targetBuffer, offset, value.X)
        buffer.writei16(targetBuffer, offset+2, value.Y)
    elseif type == "Region3int16" then
        BufferWriter.Write(targetBuffer, offset, value.Min)
        BufferWriter.Write(targetBuffer, offset+6, value.Max)
    elseif type == "EnumItem" then
        BufferWriter.Write(targetBuffer, offset, `{tostring((value :: EnumItem).EnumType)}.{(value :: EnumItem).Name}`)
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
    elseif type == "Vector3int16" then
        return Vector3int16.new(
            buffer.readf32(targetBuffer, offset),
            buffer.readf32(targetBuffer, offset+2),
            buffer.readf32(targetBuffer, offset+4)
        ), BYTE_SIZES.Vector3int16
    elseif type == "Vector2" then
        return Vector2.new(
            buffer.readf32(targetBuffer, offset),
            buffer.readf32(targetBuffer, offset+4)
        ), BYTE_SIZES.Vector2
    elseif type == "Vector2int16" then
        return Vector2int16.new(
            buffer.readf32(targetBuffer, offset),
            buffer.readf32(targetBuffer, offset+2)
        ), BYTE_SIZES.Vector2int16
    elseif type == "Region3" then
        local min = BufferWriter.Read(targetBuffer, offset, "Vector3")
        local max = BufferWriter.Read(targetBuffer, offset+12, "Vector3")
        return Region3.new(min, max), BYTE_SIZES.Region3
    elseif type == "Region3int16" then
        local min = BufferWriter.Read(targetBuffer, offset, "Vector3int16")
        local max = BufferWriter.Read(targetBuffer, offset+6, "Vector3int16")
        return Region3int16.new(min, max), BYTE_SIZES.Region3int16
    elseif type == "EnumItem" then
        local stream, size = BufferWriter.Read(targetBuffer, offset, "string")
        local hierarchy = stream:split('.')
        return Enum[hierarchy[1]][hierarchy[2]], size
    elseif type == "BrickColor" then
        return buffer.readi16(targetBuffer, offset), BYTE_SIZES.BrickColor
    elseif type == "Color3" then
        return Color3.fromRGB(
            buffer.readf32(targetBuffer, offset),
            buffer.readf32(targetBuffer, offset+4),
            buffer.readf32(targetBuffer, offset+8)
        ), BYTE_SIZES.Color3
    elseif type == "DateTime" then
        return DateTime.fromUnixTimestampMillis(buffer.readf64(targetBuffer, offset)), BYTE_SIZES.DateTime
    elseif type == "UDim" then
        return UDim.new(buffer.readf32(targetBuffer, offset), buffer.readi32(targetBuffer, offset+4)), BYTE_SIZES.UDim
    elseif type == "UDim2" then
        return UDim2.new(BufferWriter.Read(targetBuffer, offset, "UDim"), BufferWriter.Read(targetBuffer, offset+8, "UDim")), BYTE_SIZES.UDim2
    elseif type == "Rect" then
        return Rect.new(BufferWriter.Read(targetBuffer, offset, "Vector3"), BufferWriter.Read(targetBuffer, offset+12, "Vector3")), BYTE_SIZES.Rect
    elseif type == "Ray" then
        return Ray.new(BufferWriter.Read(targetBuffer, offset, "Vector3"), BufferWriter.Read(targetBuffer, offset+12, "Vector3")), BYTE_SIZES.Ray
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