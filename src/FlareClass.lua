local Symbol = require(script.Parent.lib.Symbol)
local Set = require(script.Parent.lib.Set)

--[=[
    @type Closure (...any) -> (...any) | thread
    @within FlareClass
]=]
type Closure = (...any) -> (...any) | thread
--[=[
    @type Reference FlareEnvironment | typeof({}) | Closure
    @within FlareClass
]=]
type Reference = FlareEnvironment | typeof({})
type InternalFlareClass<K, V> = {
    __index: (self: FlareEnvironment, key: K) -> (V),
    __newindex: (self: FlareEnvironment, key: K, value: V) -> ();
    ReferenceClosure: (self: FlareEnvironment, closure: Closure) -> (Closure),
    FriendReference: (self: FlareEnvironment, reference: Reference) -> (),
    UnfriendReference: (self: FlareEnvironment, reference: Reference) -> (),
    LockProperty: (self: FlareEnvironment, propertyName: K) -> (),
    UnlockProperty: (self: FlareEnvironment, propertyName: K) -> (),
    StrictifyProperty: (self: FlareEnvironment, propertyName: K, predicate: (value: V) -> (boolean)) -> (),
    ReferenceId: Symbol.Symbol
}
export type FlareClass = typeof(setmetatable({} :: {[Symbol.Symbol<"OBJECT_REFERENCE_ID">]: string}, {} :: InternalFlareClass))
export type RawFlareClass<T...> = {
    FlareInit: (self: FlareEnvironment<T...>, T...) -> (),
    Extend: () -> (FlareClass<T...>)
}

local PRIVATE_MARKED_METHODS = Set('ReferenceClosure', 'FriendReference', 'UnfriendReference', 'LockProperty', 'UnlockProperty', 'StrictifyProperty')

--[=[
    @type FlareEnvironments {[Symbol]: FlareEnvironment}
    @within FlareClass
]=]
--[=[
    @interface FlareEnvironment
    @private
    @field [Symbol("PUBLIC")] {[any]: any} -- Contains public properties
    @field [Symbol("PROTECTED")] {[any]: any} -- Contains protected properties
    @field [Symbol("PRIVATE")] {[any]: any} -- Contains private properties
    @field [Symbol("REFERENCES")] {[string]: Reference} -- A marker that holds all current functions, threads, coroutines, and table references used for identifying specified access
    @within FlareClass
]=]
local FlareEnvironments = {}
local InternalFlareClass = {}
function InternalFlareClass:ReferenceClosure(closure: Closure): (Closure)
    
end

function InternalFlareClass:LockProperty(reference: Reference): Reference
    
end

function InternalFlareClass:UnlockProperty<K>(propertyName: K)
    
end

function InternalFlareClass:FriendReference<K>(propertyName: K)
    
end

function InternalFlareClass:UnfriendReference(reference: Reference)
    
end

function InternalFlareClass:StrictifyProperty(reference: Reference)
    
end

local InternalFlareClassMetatable = {}
function InternalFlareClassMetatable:__index<K, V>(key: K): V
    
end

local FlareClassMetatable = {}
--[=[
    @function new
    @param ... any
    @yields
    @within FlareClass

    Initializes the background and important processes. Calls `FlareClass:Init()` right after; once the process is complete, the method will lock `FlareClass:FriendReference()`, `FlareClass:UnfriendReference()`, and `FlareClass:StrictifyProperty()`
]=]
function FlareClassMetatable.new(...: any)
end
--[=[
    @method FlareInit
    @param ... any
    @yields

    Called after `FlareClass.new()` is invoked.
    Every initialization process __must__ be done here.

    `FlareClass:StrictifyProperty()` can only be used within this process. The method is locked afterwards.

    @within FlareClass
]=]
function FlareClassMetatable:FlareInit(...: any)
end

--[=[
    @class FlareClass
    @tag Core
    **FlareClass** is the backbone of every `FlareControllers` and `FlareServices`. This library can be used freely anywhere due to it basically being a "stricter" version of a vanilla LuaU class.
    
    The library forces a compiled class to have access specifiers; making it rather similar to a C++ class. The current specifiers present for properties are `public`, `private`, and `protected`. This also offers property locking, constant properties, and strict properties.

    Refer to the table below for the difference of access specifiers:
    
    Access Specifier | Example | Description
    --- | --- | ---
    **`public`** | `self.PublicMessage = "I'm publicly available!"` | Generic index ing, no additional or complex processes are done.
    **`protected`** | `self._protectedMessage = "I still publicly available but you can't change me!"` | Denoted by a single understore (`_`). The property in detail can still be accessed externally, albeit cannot be changed. Changing the value externally will result in an ereror.
    **`private`** | `self.__privateMessage = "I'm hidden..."` | Denoted by a double underscore (`_`). The property in detail cannot be accessed externally and will result in an error upon changing or indexing the value from an outside source.
]=]
local FlareClass = {}
function FlareClass.new(): (RawFlareClass)
    --[=[
        @private
        @prop ReferenceID Symbol
        @within FlareClass
    ]=]
    local flareClass = {}
    flareClass.__index = flareClass
    setmetatable(FlareClass, flareClass)
    for metaProp, metaVal in pairs(FlareClassMetatable) do
        flareClass[metaProp] = metaVal
    end
    return flareClass
end

return FlareClass