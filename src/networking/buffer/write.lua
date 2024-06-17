--!native
---@diagnostic disable: undefined-global

local MAX_SIZE = 1073741824

local datatypes = require(script.Parent.datatypes)
local Types = require(script.Parent.types)

type BufferWriter = Types.BufferWriter

local function assertSize(size: number, offset: number, cursor: number): number
    local place = cursor + offset
    if place > size or place <= 0 then
        error("buffer cursor out of bounds")
    end
    return offset
end

local function resizeBuffer(writer: BufferWriter, desiredSize: number): any
	if desiredSize > MAX_SIZE then
		error(`cannot resize buffer to {desiredSize} bytes (max size: {MAX_SIZE} bytes)`, 3)
	end
	writer._size = math.max(writer._size, desiredSize)
	if desiredSize < buffer.len(writer._buffer) then
		return
	end
	local oldBuffer = writer._buffer
	local newBuffer = buffer.create(desiredSize)
	buffer.copy(newBuffer, 0, oldBuffer, 0)
	writer._buffer = newBuffer
end

local writeMetatable = {}
writeMetatable.__index = writeMetatable

-- hide alloc from typed
function writeMetatable:alloc(size: number)
    resizeBuffer(self, self.Cursor + size)
end

function writeMetatable:writei8(input: number)
    self:alloc(1)
    local offset = assertSize(self._size, 1, self.Cursor)
    buffer.writei8(self._buffer, self.Cursor, input)
    self.Cursor += offset
end

function writeMetatable:writei16(input: number)
    self:alloc(2)
    local offset = assertSize(self._size, 2, self.Cursor)
    buffer.writei16(self._buffer, self.Cursor, input)
    self.Cursor += offset
end

function writeMetatable:writei32(input: number)
    self:alloc(4)
    local offset = assertSize(self._size, 4, self.Cursor)
    buffer.writei32(self._buffer, self.Cursor, input)
    self.Cursor += offset
end

function writeMetatable:writeu8(input: number): number
    self:alloc(1)
    local offset = assertSize(self._size, 1, self.Cursor)
    buffer.writeu8(self._buffer, self.Cursor, input)
    self.Cursor += offset
end

function writeMetatable:writeu16(input: number)
    self:alloc(2)
    local offset = assertSize(self._size, 2, self.Cursor)
    buffer.writeu16(self._buffer, self.Cursor, input)
    self.Cursor += offset
end

function writeMetatable:writeu32(input: number)
    self:alloc(4)
    local offset = assertSize(self._size, 4, self.Cursor)
    buffer.writeu32(self._buffer, self.Cursor, input)
    self.Cursor += offset
end

function writeMetatable:writef32(input: number)
    self:alloc(4)
    local offset = assertSize(self._size, 4, self.Cursor)
    buffer.writef32(self._buffer, self.Cursor, input)
    self.Cursor += offset
end

function writeMetatable:writef64(input: number)
    self:alloc(8)
    local offset = assertSize(self._size, 8, self.Cursor)
    buffer.writef64(self._buffer, self.Cursor, input)
    self.Cursor += offset
end

function writeMetatable:writebool(bool: boolean)
    self:writeu8(if bool == true then 1 else 0)
end

function writeMetatable:writestring(str: string, length: number?)
	local len = if length then math.min(#str, length) else #str
	local size = len + 4
    self:alloc(size)
	buffer.writeu32(self._buffer, self.Cursor, len)
	buffer.writestring(self._buffer, self.Cursor + 4, str, len)
	self.Cursor += size
end

function writeMetatable:writerawstring(str: string, length: number?)
	local len = if length then math.min(#str, length) else #str
    self:alloc(len)
	buffer.writestring(self._buffer, self.Cursor, str, length)
	self.Cursor += len
end

function writeMetatable:writetype<T>(datatype: any, input: any): T
    local type = datatypes.ReadWrite[datatypes.DataTypeToString[datatype] or datatype]
    if not type then
        error(`unsupported datatype, got "{datatype}"`)
    end
    type.write(self, input)
end

function writeMetatable:writearray(array: {any})
    local tableCount = #array
    local values, valueTypes = datatypes.WriteDynamicOutput(array, 2)
    self:writeu32(tableCount)
    if tableCount > 0 then
        for i = 1, tableCount do
            local type = valueTypes[i]
            local isRobloxType = type:sub(#type) == '$'
            local robloxType = type:sub(1, #type-1)
            self:writestring(type)
            if isRobloxType then
                self:writetype(robloxType, values[i])
            else
                self[`write{type}`](self, values[i])
            end
        end
    end
end

function writeMetatable:writemap(map: {[string]: any})
    local tableCount = 0 do
        for _ in map do
            tableCount += 1
        end
    end
    local keys, keyTypes = datatypes.WriteDynamicOutput(map, 1)
    local values, valueTypes = datatypes.WriteDynamicOutput(map, 2)
    self:writeu32(tableCount)
    if tableCount > 0 then
        for i = 1, tableCount do
            do
                local type = keyTypes[i]
                local isRobloxType = type:sub(#type) == '$'
                local robloxType = type:sub(1, #type-1)
                self:writestring(type)
                if isRobloxType then
                    self:writetype(robloxType, keys[i])
                else
                    self[`write{type}`](self, keys[i])
                end
            end do
                local type = valueTypes[i]
                local isRobloxType = type:sub(#type) == '$'
                local robloxType = type:sub(1, #type-1)
                self:writestring(type)
                if isRobloxType then
                    self:writetype(robloxType, values[i])
                else
                    self[`write{type}`](self, values[i])
                end
            end
        end
    end
end

function writeMetatable:writeenum(enum: EnumItem)
    self:writestring(tostring(enum.EnumType))
    self:writestring(enum.Name)
end

function writeMetatable:writeinstance(instance: Instance)
    self:writestring(instance:GetFullName())
end

function writeMetatable:getbuffer()
    return self._buffer
end

local write = {}
function write.new(size: number): BufferWriter
    local self = {}
    self._size = size
    self._buffer = buffer.create(size)
    self.Cursor = 0
    setmetatable(self, writeMetatable)
    return self
end

return write