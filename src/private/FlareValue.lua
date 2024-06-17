
local Signal = require(script.Parent.Parent.util.Signal)

export type Signal = Signal.Signal
export type Connection = Signal.Connection
export type FlareValue<T> = {
    Changed: Signal.Signal<T, T>;
    Set: (self: FlareValue<T>, value: T, forceValue: boolean?) -> ();
    Get: (self: FlareValue<T>) -> (T),
    Destroy: (self: FlareValue<T>) -> (),
}

local FlareValueMetatable = {}
FlareValueMetatable.__index = FlareValueMetatable
function FlareValueMetatable:Set<T>(value: T, forceValue: boolean?)
    local old = self._value
    if old ~= value or forceValue then
        if self._locked then
            error("cannot override a locked value")
        end
        if type(self._predicate) == "function" then
            assert(self._predicate(value))
        end
        self._value = value
        self.Changed:Fire(value, old)
    end
end

function FlareValueMetatable:Get<T>(): (T)
    return self._value
end

function FlareValueMetatable:LockValue()
    self._locked = true
end

function FlareValueMetatable:UnlockValue()
    self._locked = false
end

function FlareValueMetatable:SetPredicate<U>(predicate: ((value: U) -> (boolean, string?))?)
    self._predicate = predicate
end

function FlareValueMetatable:Destroy()
    self.Changed:Destroy()
    self._value = nil
    setmetatable(self, nil)
end

local FlareValue = {}
function FlareValue.new<T>(value: T): FlareValue<T>
    local self = {}
    self.Changed = Signal.new()
    self._predicate = nil
    self._locked = false
    self._value = value
    setmetatable(self, FlareValueMetatable)
    self.Changed:Fire(value)
    return self
end

return FlareValue