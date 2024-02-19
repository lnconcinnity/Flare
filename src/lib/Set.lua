--!native
--[=[
    @class Set
    Converts an array of strings into key-value pairs
]=]
--[=[
    @type Set {[string]: boolean}
    @within Set
]=]
return function(...: string): ({[string]: boolean})
    local pairs = {}
    for _,k in {...} do
        pairs[k] = true
    end
    return pairs
end