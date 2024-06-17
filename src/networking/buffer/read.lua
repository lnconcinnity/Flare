--!native
---@diagnostic disable: undefined-global

local datatypes = require(script.Parent.datatypes)
local types = require(script.Parent.types)

type BufferReader = types.BufferReader

local function assertSize(size: number, offset: number, cursor: number): number
    local place = cursor + offset
    if place > size or place <= 0 then
        error("buffer cursor out of bounds")
    end
    return offset
end

local function readTableOutputFrom(from)
    local type = from:readstring()
    local robloxType = type:sub(1, #type-1)
    local isRobloxType = type:sub(#type) == '$'
    return if isRobloxType then from:readtype(robloxType) else from[`read{type}`](from)
end

local readMetatable = {}
readMetatable.__index = readMetatable

function readMetatable:readi8(): number
    local offset = assertSize(self._size, 1, self.Cursor)
    local out = buffer.readi8(self._buffer, self.Cursor)
    self.Cursor += offset
    return out
end

function readMetatable:readi16(): number
    local offset = assertSize(self._size, 2, self.Cursor)
    local out = buffer.readi16(self._buffer, self.Cursor)
    self.Cursor += offset
    return out
end

function readMetatable:readi32(): number
    local offset = assertSize(self._size, 4, self.Cursor)
    local out = buffer.readi32(self._buffer, self.Cursor)
    self.Cursor += offset
    return out
end

function readMetatable:readu8(): number
    local offset = assertSize(self._size, 1, self.Cursor)
    local out = buffer.readu8(self._buffer, self.Cursor)
    self.Cursor += offset
    return out
end

function readMetatable:readu16(): number
    local offset = assertSize(self._size, 2, self.Cursor)
    local out = buffer.readu16(self._buffer, self.Cursor)
    self.Cursor += offset
    return out
end

function readMetatable:readu32(): number
    local offset = assertSize(self._size, 4, self.Cursor)
    local out = buffer.readu32(self._buffer, self.Cursor)
    self.Cursor += offset
    return out
end

function readMetatable:readf32(): number
    local offset = assertSize(self._size, 4, self.Cursor)
    local out = buffer.readf32(self._buffer, self.Cursor)
    self.Cursor += offset
    return out
end

function readMetatable:readf64(): number
    local offset = assertSize(self._size, 8, self.Cursor)
    local out = buffer.readf64(self._buffer, self.Cursor)
    self.Cursor += offset
    return out
end

function readMetatable:readbool(): boolean
    local out = self:readu8()
    return out == 1
end

function readMetatable:readstring(): string
    local len = self:readu32()
    local offset = assertSize(self._size, len, self.Cursor)
    local str = buffer.readstring(self._buffer, self.Cursor, len)
    self.Cursor += offset
    return str
end

function readMetatable:readrawstring(length: number): string
	local len = math.max(0, math.floor(length))
    local offset = assertSize(self._size, len, self.Cursor)
    local s = buffer.readstring(self._buffer, self.Cursor, len)
	self.Cursor += offset
	return s
end

function readMetatable:readtype<T>(datatype): T
    local type = datatypes.ReadWrite[datatypes.DataTypeToString[datatype] or datatype]
    if not type then
        error(`unsupported datatype, got "{datatype}"`)
    end
    return type.read(self)
end

function readMetatable:readarray()
    local array = {}
    for _ = 1, self:readu32() do
        local value = readTableOutputFrom(self)
        array[#array+1] = value
    end
    return array
end

function readMetatable:readmap()
    local map = {}
    for _ = 1, self:readu32() do
        local key = readTableOutputFrom(self)
        local value = readTableOutputFrom(self)
        map[key] = value
    end
    return map
end

function readMetatable:readenum()
    return Enum[self:readstring()][self:readstring()]
end

function readMetatable:readinstance()
    local source = self:readstring()
    local content = string.split(source, '.')
    if content[1] == game:GetFullName() then
        return nil
    end
    local count = #content
    local instance = if content[1] == "Workspace" then workspace else game:GetService(content[1])
    for i = 2, count do
        if not instance then
            break
        end
        instance = instance:FindFirstChild(content[i])
    end
    return instance
end

local read = {}
function read.new(buf): BufferReader
    local self = {}
    self._size = buffer.len(buf)
    self._buffer = buf
    self.Cursor = 0
    setmetatable(self, readMetatable)
    return self
end

return read