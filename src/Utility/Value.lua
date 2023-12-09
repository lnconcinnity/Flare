local Signal = require(script.Parent.Signal)

type Value = {
    Value: any,
    Changed: typeof(Signal.new())
}

local ValueAPI = {}
function ValueAPI:set<T>(newValue: T, forceValue: boolean)
    if (self.Value ~= newValue or forceValue == true) and self._valueLocked == false then
        self.Changed:FireDeferred(self.Value)
        self.Value = newValue
    end
end

function ValueAPI:get<T>(): T
    return self.Value
end

function ValueAPI:lock()
    self._valueLocked = true
end

function ValueAPI:unlock()
    self._valueLocked = false
end

local Value = {}
Value.__index = ValueAPI
function Value.new<T>(initialValue: T): Value
    local self = {}
    self._valueLocked = false
    self.Value = initialValue
    self.Changed = Signal.new()
    setmetatable(self, Value)
    return self
end

return Value