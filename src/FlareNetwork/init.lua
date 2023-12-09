local Remote = require(script.Remote)

local function GetFolder(folderName: string)
    local folder = script:FindFirstChild(folderName)
    if not folder then
        folder = Instance.new("Folder")
        folder.Parent = script
    end
    return folder
end

local FlareNetworkAPI

local FlareNetwork = {}
FlareNetwork.__index = FlareNetworkAPI
FlareNetwork.MakeRemote = Remote.new

function FlareNetwork.new()
    
end


return FlareNetworkAPI