local FlareClass = require(script.Parent.Utility.FlareClass)

local FLARE_OBJECT_TEMPLATE = FlareClass.extend()
FLARE_OBJECT_TEMPLATE.Name = "TemplateObject"
function FLARE_OBJECT_TEMPLATE:FlareInit()
    warn(self.Name .. ":FlareInit() has not yet been overridden")
end

function FLARE_OBJECT_TEMPLATE:FlareStart()
    warn(self.Name .. ":FlareStart() has not yet been overridden")
end

local FLARE_ACTOR_TEMPLATE = FlareClass.extend()
function FLARE_ACTOR_TEMPLATE:FlareInit()
    warn(script:GetActor() .. ":FlareInit() has not yet been overridden")
end

function FLARE_ACTOR_TEMPLATE:cleanup()
    warn(script:GetActor() .. ":cleanup() has not yet been overridden")
end

local function GetFlareObject()
    if script:GetActor() then
        error("Please use Instances.GetFlareActor() instead, or make an entirely different luau/flare class.")
    end
    return FLARE_OBJECT_TEMPLATE.extend()
end

local function GetFlareActor()
    if not script:GetActor() then
        error("Cannot use Instances.GetFlareActor() on an actorless source.")
    end
end

return {
    GetFlareActor = GetFlareActor,
    GetFlareObject = GetFlareObject,
}