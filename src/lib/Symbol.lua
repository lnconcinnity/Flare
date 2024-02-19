--!native

--[=[
    @class Symbol
    Custom user-made identifiers using proxies
]=]
local function makeSymbol<S>(name: S): Symbol
    local proxy = newproxy(true)
    getmetatable(proxy).__tostring = function()
        return `Symbol<{name}>`
    end
    return proxy
end
--[=[
    @type Symbol typeof(Symbol<string>("Test"))
    @within Symbol
]=]
export type Symbol<S> = typeof(makeSymbol<"Test">("Test"))
return makeSymbol