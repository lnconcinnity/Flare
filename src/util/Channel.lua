--!native

export type Channel<T> = {
    Flush: (self: Channel<T>) -> ({T}),
    Dump: (self: Channel<T>, input: T) -> (),
    Destroy: (self: Channel<T>) -> (),
}

local ChannelMetatable = {}
ChannelMetatable.__index = ChannelMetatable
function ChannelMetatable:Dump<T>(input: T)
    self._queue[#self._queue+1] = input
end

function ChannelMetatable:Flush<T>(): {T}
    if #self._queue <= 0 then return {} end
    local flushedQueue = self._queue
    self._queue = {}
    return flushedQueue
end

function ChannelMetatable:Destroy()
    self._queue = nil
    setmetatable(self, nil)
end

local Channel = {}
function Channel.new<T>(): Channel<T>
    return setmetatable({_queue = {} :: {T}}, ChannelMetatable)
end

return Channel