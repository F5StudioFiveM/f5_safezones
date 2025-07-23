Framework = {}

local RESOURCE_NAME = GetCurrentResourceName()
local SIDE = IsDuplicityVersion() and 'SERVER' or 'CLIENT'

local COLORS = {
    error   = '^1',
    warn    = '^3',
    info    = '^5',
    success = '^2',
    debug   = '^4',
    reset   = '^0'
}

function Framework.Log(level, msg, ...)
    if level ~= 'error' and Config and Config.BridgeLog == false then
        return
    end
    local color = COLORS[level] or COLORS.info
    local prefix = string.format('%s[%s:bridge:%s]%s', color, RESOURCE_NAME, SIDE, COLORS.reset)
    if select('#', ...) > 0 then
        local ok, formatted = pcall(string.format, msg, ...)
        msg = ok and formatted or msg
    end
    print(prefix .. ' ' .. msg)
end

local FRAMEWORKS = {
    { name = 'qbox',   resource = 'qbx_core' },
    { name = 'qbcore', resource = 'qb-core' },
    { name = 'esx',    resource = 'es_extended' }
}

local function detectFramework()
    for _, fw in ipairs(FRAMEWORKS) do
        local state = GetResourceState(fw.resource)
        if state == 'started' then
            return fw.name, fw.resource
        end
    end
    return nil, nil
end

CreateThread(function()
    Framework.Log('info', 'Starting framework detection...')
    Framework.Log('debug', 'Detection priority: QBox -> QBCore -> ESX')

    local attempts = 0
    local detectedResource
    while not Framework.Name and attempts < 300 do
        Framework.Name, detectedResource = detectFramework()
        if Framework.Name then break end
        attempts = attempts + 1
        Wait(100)
    end

    if not Framework.Name then
        Framework.Log('error', 'No supported framework detected after %d attempts (%.1fs)', attempts, attempts * 0.1)
        Framework.Log('error', 'Resource states:')
        for _, fw in ipairs(FRAMEWORKS) do
            Framework.Log('error', '  %s (%s): %s', fw.name, fw.resource, GetResourceState(fw.resource))
        end
        Framework.IsReady = true
        return
    end

    Framework.Log('success', 'Framework detected: %s (resource: %s) after %d attempt(s)', Framework.Name, detectedResource, attempts + 1)
    Framework.IsReady = true
end)

function Framework.WaitForReady()
    while not Framework.IsReady do
        Wait(10)
    end
end
