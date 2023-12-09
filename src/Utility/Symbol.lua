local SYMBOL_KEY_PRESET = "Symbol<%s>"

local function makeSymbol(symbolName: string)
    local symbolKey = SYMBOL_KEY_PRESET:format(symbolName)
    local proxy = newproxy(true)
    getmetatable(proxy).__tostring = function()
        return symbolKey
    end
    return proxy
end

return makeSymbol