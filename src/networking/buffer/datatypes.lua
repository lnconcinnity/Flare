--!native

local Types = require(script.Parent.types)

type BufferReader = Types.BufferReader
type BufferWriter = Types.BufferWriter

local ReadWrite = nil
ReadWrite = {
    ['BrickColor'] = {
        size = 2,
        read = function(read: BufferReader): BrickColor
            return BrickColor.new(read:readi16())
        end,
        write = function(write: BufferWriter, input: BrickColor)
            write:writei16(input.Number)
        end
    },
    ['Color3'] = {
        size = 12,
        read = function(read: BufferReader): Color3
            return Color3.fromRGB(read:readf32(), read:readf32(), read:readf32())
        end,
        write = function(write: BufferWriter, input: Color3)
            write:writef32(input.R)
            write:writef32(input.G)
            write:writef32(input.B)
        end
    },
    ['CFrame'] = {
        size = 48,
        read = function(read: BufferReader): CFrame
            return CFrame.fromMatrix(ReadWrite.Vector3.read(read), ReadWrite.Vector3.read(read), ReadWrite.Vector3.read(read), ReadWrite.Vector3.read(read))
        end,
        write = function(write: BufferWriter, input: CFrame)
            ReadWrite.Vector3.write(write, input.Position)
            ReadWrite.Vector3.write(write, input.XVector)
            ReadWrite.Vector3.write(write, input.YVector)
            ReadWrite.Vector3.write(write, input.LookVector)
        end
    },
    ['Vector2'] = {
        size = 8,
        read = function(read: BufferReader): Vector2
            return Vector2.new(read:readf32(), read:readf32())
        end,
        write = function(write: BufferWriter, input: Vector2)
            write:writef32(input.X)
            write:writef32(input.Y)
        end
    },
    ['Vector3'] = {
        size = 12,
        read = function(read: BufferReader): Vector3
            return Vector3.new(read:readf32(), read:readf32(), read:readf32())
        end,
        write = function(write: BufferWriter, input: Vector3)
            write:writef32(input.X)
            write:writef32(input.Y)
            write:writef32(input.Z)
        end
    },
    ['Vector2int16'] = {
        size = 4,
        read = function(read: BufferReader): Vector2int16
            return Vector2int16.new(read:readi16(), read:readi16())
        end,
        write = function(write: BufferWriter, input: Vector2)
            write:writei16(input.X)
            write:writei16(input.Y)
        end
    },
    ['Vector3int16'] = {
        size = 6,
        read = function(read: BufferReader): Vector3int16
            return Vector3int16.new(read:readi16(), read:readi16(), read:readi16())
        end,
        write = function(write: BufferWriter, input: Vector3int16)
            write:writei16(input.X)
            write:writei16(input.Y)
            write:writei16(input.Z)
        end
    },
    ['DateTime'] = {
        size = 8,
        read = function(read: BufferReader): DateTime
            return DateTime.fromUnixTimestampMillis(read:readf64())
        end,
        write = function(write: BufferWriter, input: DateTime)
            write:writef64(input.UnixTimestampMillis)
        end
    },
    ['Ray'] = {
        size = 24,
        read = function(read: BufferReader): Ray
            return Ray.new(ReadWrite.Vector3.read(read), ReadWrite.Vector3.read(read))
        end,
        write = function(write: BufferWriter, input: Ray)
            ReadWrite.Vector3.write(write, input.Origin)
            ReadWrite.Vector3.write(write, input.Direction)
        end
    },
    ['Rect'] = {
        size = 16,
        read = function(read: BufferReader): Rect
            return Rect.new(ReadWrite.Vector2.read(read), ReadWrite.Vector2.read(read))
        end,
        write = function(write: BufferWriter, input: Rect)
            ReadWrite.Vector2.write(write, input.Min)
            ReadWrite.Vector2.write(write, input.Max)
        end
    },
    ['Region3'] = {
        size = 24,
        read = function(read: BufferReader): Region3
            return Region3.new(ReadWrite.Vector3.read(read), ReadWrite.Vector3.read(read))
        end,
        write = function(write: BufferWriter, input: Region3)
            local pos = input.CFrame.Position
            local sizeHalf = input.Size * 0.5
            local min = pos - sizeHalf
            local max = pos + sizeHalf
            ReadWrite.Vector3.write(write, min)
            ReadWrite.Vector3.write(write, max)
        end
    },
    ['Region3int16'] = {
        size = 12,
        read = function(read: BufferReader): Region3int16
            return Region3int16.new(ReadWrite.Vector3int16.read(read), ReadWrite.Vector3int16.read(read))
        end,
        write = function(write: BufferWriter, input: Region3int16)
            ReadWrite.Vector3int16.write(write, input.Min)
            ReadWrite.Vector3int16.write(write, input.Max)
        end
    },
    ['UDim'] = {
        size = 8,
        read = function(read: BufferReader): UDim
            return UDim.new(read:readf32(), read:readi32())
        end,
        write = function(write: BufferWriter, input: UDim)
            write:writef32(input.Scale)
            write:writei32(input.Offset)
        end
    },
    ['UDim2'] = {
        size = 16,
        read = function(read: BufferReader): UDim2
            return UDim2.new(ReadWrite.UDim.read(read), ReadWrite.UDim.read(read))
        end,
        write = function(write: BufferWriter, input: UDim2)
            ReadWrite.UDim.write(write, input.X)
            ReadWrite.UDim.write(write, input.Y)
        end
    },
}

local DataTypeToString = {
	[BrickColor] = "BrickColor",
	[CFrame] = "CFrame",
	[Color3] = "Color3",
	[DateTime] = "DateTime",
	[Ray] = "Ray",
	[Rect] = "Rect",
	[Region3] = "Region3",
	[Region3int16] = "Region3int16",
	[UDim] = "UDim",
	[UDim2] = "UDim2",
	[Vector2] = "Vector2",
	[Vector3] = "Vector3",
	[Vector2int16] = "Vector2int16",
	[Vector3int16] = "Vector3int16",
}

local datatypes;
datatypes = {
    ReadWrite = ReadWrite,
    DataTypeToString = DataTypeToString,
    AssumeNumberSize = function(value: string): (string, string)
        local is_float = select(2, math.modf(value)) > 0
        local len = #tostring(value)
        len = if is_float then len - 1 else len
        local cast = if is_float then 'f' elseif value < 2^32 and value > 0 then 'u' else 'i'
        local sizecast = if cast == 'i' then (
            if value >= -128 and value <= 127 then '8'
            elseif value >= -32_768 and value <= 32_767 then '16'
            else '32'
        ) elseif cast == 'u' then (
            if value <= 255 then '8'
            elseif value <= 65_535 then '16'
            else '32'
        ) else (
            if len <= 15 then '64' else '32'
        )
        return cast, sizecast
    end,
    WriteDynamicOutput = function(source: {}, mode: number): ({any},{string})
        local get_type = function(value)
            local type = typeof(value)
            if type == "number" then
                local cast, sizecast = datatypes.AssumeNumberSize(value)
                type = cast..sizecast
            elseif type == "boolean" then
                type = "bool"
            elseif type == "table" then
                type = if value[1] ~= nil then 'array' else 'map'
            elseif type ~= "string" then
                type = type..'$'
            end
            return type
        end
        local input, types = {}, {}
        for _key, _value in source do
            local target = if mode == 1 then _key else _value
            input[#input+1] = target
            types[#types+1] = get_type(target)
        end
        return input, types
    end
}

return datatypes