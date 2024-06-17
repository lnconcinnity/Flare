--!native

--[=[
    @class Symbol
    Custom user-made identifiers using proxies
]=]
local function makeSymbol<S>(name: S): Symbol<S>
    local proxy = newproxy(true)
    local metadata = nil
    local proxymt = getmetatable(proxy)
    proxymt.__tostring = function()
        return string.format("Symbol<%s>", name)
    end
    proxymt.__index = function(_, key)
        if key:lower() == "metadata" then
            return metadata
        end
    end
    proxymt.__call = function(_, value)
        metadata = value
        return proxy
    end
    return proxy
end
--[=[
    @type Symbol typeof(Symbol<string>("Test"))
    @within Symbol
]=]
export type Symbol<S> = typeof(makeSymbol("Test"))
return makeSymbol