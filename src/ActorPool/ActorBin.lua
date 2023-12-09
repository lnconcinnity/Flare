type TaskInfo = {
    task: string,
    target: string,
    args: {any},
}

return function (actorInstance: Actor): () -> ()
    local subscriber = actorInstance:WaitForChild("Subscriber")
    local factory = subscriber:WaitForChild("FactoryReference").Value
    factory = require(factory)
    local requestEnd = subscriber:WaitForChild("RequestEnd") :: BindableEvent;
    local hasCleanup = type(factory.cleanup) == "function"
    
    (subscriber:WaitForChild("RequestStart") :: BindableEvent).Event:ConnectParallel(function(taskInfo: TaskInfo)
        local factoryObject = factory.new()
        local args = table.pack(select(2, xpcall(factoryObject[taskInfo.target], warn, factoryObject, table.unpack(taskInfo.args))))
        if hasCleanup then
            factoryObject:cleanup()
        end
        requestEnd:Fire(taskInfo.task, if args.n > 0 then table.unpack(args) else nil)
    end)
end