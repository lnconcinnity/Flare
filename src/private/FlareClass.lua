local HttpService = game:GetService("HttpService")
local Symbol = require(script.Parent.Parent.util.Symbol)
local Set = require(script.Parent.Parent.util.Set)
local C = require(script.Parent.C)
local FlareValue = require(script.Parent.FlareValue)

--[=[
    A FlareCLass is a custom-implemented version of a standard OOP class.
]=]

type FlareEnvironment<T, U> = {
    [Symbol.Symbol<"PUBLIC" | "PROTECTED" | "PRIVATE" | "REFERENCES">]: {[T]: U},
    -- hide .WrappedInternals
}
type Closure = (...any) -> (...any) | thread
type Reference = FlareEnvironment<any, any> | typeof({})
type InternalFlareClass<T, U> = {
    __index: (self: FlareClass<T, U>, key: T) -> (U),
    __newindex: (self: FlareClass<T, U>, key: T, value: U) -> ();
    Reference: (self: FlareClass<T, U>, closure: Closure) -> (Closure),
    Dereference: (self: FlareClass<T, U>, closure: Closure) -> (),
    FriendReference: (self: FlareClass<T, U>, reference: Reference) -> (),
    UnfriendReference: (self: FlareClass<T, U>, reference: Reference) -> (),
    LockProperty: (self: FlareClass<T, U>, propertyName: T) -> (),
    UnlockProperty: (self: FlareClass<T, U>, propertyName: T) -> (),
    StrictifyProperty: (self: FlareClass<T, U>, propertyName: T, predicate: (value: U) -> (boolean)) -> (),
    GarbageCollectValue: (self: FlareClass<T, U>, propertyName: T) -> (boolean),
}
type ExpsoedFlareClas<T, U> = {
    GetPropertyChangedSignal: (self: FlareClass<T, U>, property: T, bound: (value: U) -> ()) -> (FlareValue.Connection),
}

export type FlareClass<T, U> = typeof(setmetatable({} :: {}, {} :: InternalFlareClass<T, U>))
export type RawFlareClass<T, U, E...> = {
    new: (T...) -> (FlareClass<T, U>),
    extend: () -> (RawFlareClass),
    FlareInit: (self: InternalFlareClass<T, U>, E...) -> (),
}

local MAX_STACK_LEVEL = 2^16
local IGNORED_STATICS = Set('FlareInit', 'new', 'extend', '__index')
local BYPASS_RAW_VALUE_FROM_REFERENCES = Set('GetPropertyChangedSignal')
local INTERNAL_ONLY = Set('Reference', 'Dereference', 'FriendReference', 'UnfriendReference', 'FreeProperty', 'LockProperty', 'UnlockProperty', 'StrictifyProperty', 'SetPropertyLevel')
local PUBLIC, PROTECTED, PRIVATE, REFERENCES, SPECIAL, ID = Symbol("PUBLIC"), Symbol("PROTECTED"), Symbol("PRIVATE"), Symbol("REFERENCES"), Symbol("SPECIAL_PROPERTIES"), Symbol("FLARE_CLASS_ID")

local function countIdentifiers(key: string): number
    local count = 0
    for _occurence, _at in key:sub(1, 2):gmatch("_") do
        count += 1
    end
    return count
end

-- the extraboolean is for the __newindex method, it denotes whether or not we should use the value (class) instead of value (raw)
local function climbStackLevelUntil<T, U>(environment: FlareEnvironment<T, U>): (boolean, boolean?)
    local level = 1
    local result = false
    local closureName = ''
    while not result do
        local info = C.getStackInfo(level)
        if not info.closure then
            break
        end
        closureName = info.closure_name
        local hasReference = environment[REFERENCES][info.closure_address] ~= nil
        if (info.line == -1 or info.line ~= -1) and hasReference then
            result = true
        elseif level >= MAX_STACK_LEVEL then
            break
        end
        level += 1
    end
    return result, BYPASS_RAW_VALUE_FROM_REFERENCES[closureName]
end

local FlareEnvironments: {[Symbol.Symbol<"FLARE_CLASS_ID">]: FlareEnvironment<any, any>} = {}

local InternalFlareClass = {}
function InternalFlareClass:Reference(reference: any): (any)
    local environment = FlareEnvironments[self[ID]]
    environment[REFERENCES][tostring(reference)] = true
    return reference
end

function InternalFlareClass:Dereference(reference: any)
    local environment = FlareEnvironments[self[ID]]
    environment[REFERENCES][tostring(reference)] = nil
end

function InternalFlareClass:LockProperty<T>(propertyName: T)
    local environment = FlareEnvironments[self[ID]]
    local rawValue = environment[PRIVATE][propertyName] or environment[PROTECTED][propertyName] or environment[PUBLIC][propertyName]
    if rawValue then
        rawValue.Locked = true
    else
        error(`cannot unlock a non-existent property, expected "{propertyName}"`, 3)
    end
end

function InternalFlareClass:UnlockProperty<T>(propertyName: T)
    local environment = FlareEnvironments[self[ID]]
    local rawValue = environment[PRIVATE][propertyName] or environment[PROTECTED][propertyName] or environment[PUBLIC][propertyName]
    if rawValue then
        if rawValue.IsConstant then
            error("fatal error. cannot unlock a constant", 3)
        end
        rawValue.Locked = false
    else
        error(`cannot unlock a non-existent property, expected "{propertyName}"`, 3)
    end
end

function InternalFlareClass:FriendReference(reference: Reference)
    local environment = FlareEnvironments[self[ID]]
    environment[REFERENCES][tostring(reference)] = true
end

function InternalFlareClass:UnfriendReference(reference: Reference)
    local environment = FlareEnvironments[self[ID]]
    environment[REFERENCES][tostring(reference)] = nil
end

function InternalFlareClass:StrictifyProperty<T, U>(propertyName: T, predicate: (value: U) -> (boolean))
    local environment = FlareEnvironments[self[ID]]
    local rawValue = environment[PRIVATE][propertyName] or environment[PROTECTED][propertyName] or environment[PUBLIC][propertyName]
    if rawValue then
        if not rawValue.IsConstant then
            rawValue:SetPredicate(predicate)
        end
    else
        warn('cannot strictify a non-existent property.')
    end
end

function InternalFlareClass:SetPropertyLevel<T>(propertyName: T, level: number)
    local environment = FlareEnvironments[self[ID]]
    local rawValue = environment[PRIVATE][propertyName] or environment[PROTECTED][propertyName] or environment[PUBLIC][propertyName]
    if rawValue then
        level = math.clamp(math.abs(math.floor(level)), 0, 2)
        local newDesignation = if level == 2 then PRIVATE elseif level == 1 then PROTECTED else PUBLIC
        environment[newDesignation][propertyName] = rawValue
        environment[SPECIAL][propertyName] = level
    end
end

function InternalFlareClass:FreeProperty<T>(propertyName: T): (boolean)
    local environment = FlareEnvironments[self[ID]]
    local rawValue = environment[PRIVATE][propertyName] or environment[PROTECTED][propertyName] or environment[PUBLIC][propertyName]
    if rawValue then
        rawValue:Destroy()
        environment[PRIVATE][propertyName] = nil
        environment[PROTECTED][propertyName] = nil
        environment[PUBLIC][propertyName] = nil
        environment[SPECIAL][propertyName] = nil
    end
    return false
end

local InternalFlareClassMetatable = {}
function InternalFlareClassMetatable:__index<K, V>(key: K): V
    local environment = FlareEnvironments[self[ID]]
    local identifierCount = countIdentifiers(key) or environment[SPECIAL][key]
    local ofInternal = INTERNAL_ONLY[key] and not BYPASS_RAW_VALUE_FROM_REFERENCES[key]
    if ofInternal then
        local accesOk, _bypassRawIndex = climbStackLevelUntil(environment)
        if accesOk then
            local wrapped = environment.WrappedInternals[key]
            if not wrapped then
                wrapped = function<T...>(...: T...): (T...)
                    return InternalFlareClass[key](...)
                end
                environment.WrappedInternals[key] = wrapped
            end
            return wrapped
        end
        error(`cannot access internal method "{key}"`)
    else
        local accesOk, bypassRawIndex = climbStackLevelUntil(environment)
        local designation = if identifierCount >= 1 then environment[PROTECTED] else environment[PUBLIC]
        if identifierCount >= 2 then
            if accesOk then
                designation = environment[PRIVATE]
            else
                error(`cannot access private "{key}"`)
            end
        end
        local value = designation[key]
        return if bypassRawIndex then value else (if type(value) == "table" and type(value.Get) == "function" then value:Get() else value)
    end
end

function InternalFlareClassMetatable:__newindex<K, V>(key: K, value: V)
    local environment = FlareEnvironments[self[ID]]
    local identifierCount = countIdentifiers(key)
    local ofInternal = INTERNAL_ONLY[key] and not BYPASS_RAW_VALUE_FROM_REFERENCES[key]
    if ofInternal then
        error(`cannot override internal members`)
    else
        local accesOk, _bypassRawIndex = climbStackLevelUntil(environment)
        local designation = environment[PUBLIC]
        if identifierCount >= 2 then
            if accesOk then
                designation = environment[PRIVATE]
            else
                error(`cannot set private "{key}" to {typeof(value)}`)
            end
        elseif identifierCount >= 1 then
            if accesOk then
                designation = environment[PROTECTED]
            else
                error(`cannot set protected "{key} to {typeof(value)}`)
            end
        end
        local flareValue: FlareValue.FlareValue<V> = designation[key]
        if not flareValue then
            local val = FlareValue.new(value)
            designation[key] = val
            flareValue = val
        end
        local old = flareValue:Get()
        flareValue:Set(value)
        local valtype, keytype = type(value), type(key)
        if valtype == "function" then
            environment[REFERENCES][tostring(old)] = nil
            environment[REFERENCES][tostring(value)] = true
        elseif keytype == "string" and (key :: string):gsub("_", ""):match("^%u+$") ~= nil then
            flareValue:LockValue()
        end
    end
end

local ExposedFlareClassAPI = {}
function ExposedFlareClassAPI:GetPropertyChangedSignal<K>(property: K, bound: Closure)
    return self[property].Changed:Connect(bound)
end

local FlareClass = {}
function FlareClass.new(): (RawFlareClass)
    local flareClass: RawFlareClass = {}
    flareClass.__index = flareClass
    setmetatable(FlareClass, flareClass)
    function flareClass.new<T...>(...: T...): (FlareClass<any, any>)
        local self = {}
        local environment = {
            [PUBLIC] = {},
            [PROTECTED] = {},
            [PRIVATE] = {},
            [SPECIAL] = {},
            [REFERENCES] = setmetatable(Set(tostring(flareClass.new), if flareClass.FlareInit then tostring(flareClass.FlareInit) else nil), {__mode = 'k'}),
            WrappedInternals = {},
        }
        self[ID] = Symbol(HttpService:GenerateGUID(false))
        FlareEnvironments[self[ID]] = environment
        setmetatable(self, InternalFlareClassMetatable)
        for propKey, propValue in pairs(flareClass) do
            if IGNORED_STATICS[propKey] then continue end
            self[propKey] = propValue
        end
        for exposedKey, exposedValue in pairs(ExposedFlareClassAPI) do
            self[exposedKey] = exposedValue
        end
        if type(flareClass.FlareInit) == "function" then
            flareClass.FlareInit(self, ...)
        end
        return self
    end
    return flareClass
end

return FlareClass