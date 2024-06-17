--!native

local C_FUNCTION_IDENTIFIER = "[C]"
local DEBUG_OPTIONS = 'anlsf'
local CLOSURE_NAMES = {'<cclosure>', '<anonymous>'}
local NONE = 'n/a'

type Closure = (...any) -> (...any) | thread
export type StackInfo = {
    arg_count: number,
    is_variadic: boolean,
    line: number,
    source: string,
    closure: Closure | nil,
    closure_name: string,
    closure_address: string,
}

local function _onDebugInfoRequestErrored(msg: string)
    warn(`[DEBUG.INFO FAULT] {msg}`)
end

local function safeGetDebugInfo(closureOrLevel: number | Closure, options: string): (number, boolean, string, number, string, ((...any) -> (...any))?)
    if type(closureOrLevel) == "number" then
        closureOrLevel = closureOrLevel + 4
        -- xpcall
        -- select
        -- safeGetDebugInfo
        -- isC / getStackInfo
    end
    return select(2, xpcall(debug.info, _onDebugInfoRequestErrored, closureOrLevel, options))
end

local C = {}
function C.isC(closureOrLevel: number | Closure): boolean
    if type(closureOrLevel) ~= "function" or type(closureOrLevel) ~= "number" then
        return false
    end
    local src, line = safeGetDebugInfo(closureOrLevel, "sl")
    return src == C_FUNCTION_IDENTIFIER and line == -1
end

function C.getStackInfo(stackLevel: number): StackInfo
    local nargs, variadic, name, line, src, closure = safeGetDebugInfo(stackLevel, DEBUG_OPTIONS)
    return {
        arg_count = nargs or -1,
        is_variadic = if variadic ~= nil then variadic else false,
        line = line or -1,
        source = src or "<c>",
        closure = closure,
        closure_name = if name ~= nil and #name > 0 then name else (if src == nil then CLOSURE_NAMES[1] else CLOSURE_NAMES[2]),
        closure_address = if closure  ~= nil then tostring(closure) else NONE,
    }
end

return C