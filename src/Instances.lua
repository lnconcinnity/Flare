local FlareClass = require(script.Parent.Utility.FlareClass)
local ActorPool = require(script.Parent.ActorPool)

local FLARE_OBJECT_TEMPLATE = FlareClass.extend()
FLARE_OBJECT_TEMPLATE.Name = "TemplateObject"
function FLARE_OBJECT_TEMPLATE:FlareInit()
    warn(self.Name .. ":FlareInit() has not yet been overridden")
end

function FLARE_OBJECT_TEMPLATE:FlareStart()
    warn(self.Name .. ":FlareStart() has not yet been overridden")
end

function FLARE_OBJECT_TEMPLATE:GetActorManager(managerName: string, targetFactory: ModuleScript?, actorCount: number?)
    assert(#managerName > 0, "Argument 1 must be a non-empty string")
    local actorContainer: {[string]: {}} = self._actors
    if not actorContainer then
        self._actors = {}
    end
    if actorContainer[managerName] then
        return actorContainer[managerName]
    end
    assert(targetFactory ~= nil, "Argument 2 must not be nil")
    assert(typeof(targetFactory) == "Instance" and targetFactory:IsA("ModuleScript"), "Argument 2 must be a ModuleScript instance")
    local manager = ActorPool.new(targetFactory, actorCount)
    actorContainer[managerName] = manager
    return manager
end
FLARE_OBJECT_TEMPLATE.post()

local FLARE_ACTOR_TEMPLATE = FlareClass.extend()
function FLARE_ACTOR_TEMPLATE:FlareInit()
    warn(script:GetActor() .. ":FlareInit() has not yet been overridden")
end

function FLARE_ACTOR_TEMPLATE:cleanup()
    warn(script:GetActor() .. ":cleanup() has not yet been overridden")
end
FLARE_ACTOR_TEMPLATE.post()

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