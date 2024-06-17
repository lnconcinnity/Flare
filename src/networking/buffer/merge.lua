--!native
return function(buffers)
    local totalSize = 0
    local mergeCount = #buffers
    if mergeCount == 0 then
        return nil
    elseif mergeCount == 1 then
        return buffers[1]
    end
    for k = 1, mergeCount do
        totalSize += buffer.len(buffers[k])
    end

    local mergedBuffer = buffer.create(totalSize)
    local bufferCursor = 0
    for k = 1, mergeCount do
        local currentBuffer = buffers[k]
        buffer.copy(mergedBuffer, bufferCursor, currentBuffer)
        bufferCursor += buffer.len(currentBuffer)
    end
    return mergedBuffer
end