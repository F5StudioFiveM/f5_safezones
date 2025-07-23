local function initQBCore()
    Framework.Log('info', 'Initializing QBCore client bridge...')

    local ok, QBCore = pcall(exports['qb-core'].GetCoreObject, exports['qb-core'])
    if not ok or not QBCore then
        Framework.Log('error', 'Failed to get QBCore object: %s', tostring(QBCore))
        return false
    end

    Framework.OnPlayerLoaded = function(cb)
        RegisterNetEvent('QBCore:Client:OnPlayerLoaded', cb)
        Framework.Log('debug', 'Registered QBCore:Client:OnPlayerLoaded event handler')
    end

    Framework.IsPlayerLoaded = function()
        return LocalPlayer.state.isLoggedIn
    end

    Framework.GetPlayerData = function()
        return QBCore.Functions.GetPlayerData()
    end

    Framework.Notify = function(message, notifType)
        QBCore.Functions.Notify(message, notifType or 'primary', 5000)
    end

    Framework.Log('success', 'QBCore client bridge initialized')
    return true
end

local function initQBox()
    Framework.Log('info', 'Initializing QBox client bridge...')

    Framework.OnPlayerLoaded = function(cb)
        AddEventHandler('QBCore:Client:OnPlayerLoaded', cb)
        Framework.Log('debug', 'Registered QBCore:Client:OnPlayerLoaded event handler (QBox local event)')
    end

    Framework.IsPlayerLoaded = function()
        return LocalPlayer.state.isLoggedIn
    end

    Framework.GetPlayerData = function()
        if QBX and QBX.PlayerData then
            return QBX.PlayerData
        end
        Framework.Log('warn', 'QBX.PlayerData not available, returning empty table')
        return {}
    end

    Framework.Notify = function(message, notifType)
        local oxType = notifType
        if notifType == 'primary' or not notifType then oxType = 'inform' end
        local ok, err = pcall(exports['ox_lib'].notify, exports['ox_lib'], {
            description = message,
            type = oxType
        })
        if not ok then
            Framework.Log('error', 'ox_lib notify failed: %s', tostring(err))
            SetNotificationTextEntry('STRING')
            AddTextComponentSubstringPlayerName(message)
            DrawNotification(false, true)
        end
    end

    Framework.Log('success', 'QBox client bridge initialized')
    return true
end

local function initESX()
    Framework.Log('info', 'Initializing ESX client bridge...')

    local ok, ESX = pcall(exports['es_extended'].getSharedObject, exports['es_extended'])
    if not ok or not ESX then
        Framework.Log('error', 'Failed to get ESX shared object: %s', tostring(ESX))
        return false
    end

    Framework.OnPlayerLoaded = function(cb)
        RegisterNetEvent('esx:playerLoaded', function()
            cb()
        end)
        Framework.Log('debug', 'Registered esx:playerLoaded event handler')
    end

    Framework.IsPlayerLoaded = function()
        return ESX.PlayerLoaded
    end

    Framework.GetPlayerData = function()
        return ESX.GetPlayerData()
    end

    Framework.Notify = function(message, notifType)
        ESX.ShowNotification(message, notifType or 'info', 5000)
    end

    Framework.Log('success', 'ESX client bridge initialized')
    return true
end

local function setNoopFunctions()
    Framework.OnPlayerLoaded = function() end
    Framework.IsPlayerLoaded = function() return false end
    Framework.GetPlayerData = function() return {} end
    Framework.Notify = function(message)
        SetNotificationTextEntry('STRING')
        AddTextComponentSubstringPlayerName(message)
        DrawNotification(false, true)
    end
end

CreateThread(function()
    Framework.WaitForReady()

    if not Framework.Name then
        Framework.Log('warn', 'No framework available, using fallback noop functions')
        setNoopFunctions()
        Framework.ClientReady = true
        return
    end

    local inits = {
        qbcore = initQBCore,
        qbox = initQBox,
        esx = initESX
    }

    local init = inits[Framework.Name]
    if init then
        local success = init()
        if not success then
            Framework.Log('error', 'Client bridge initialization failed for %s, using fallback', Framework.Name)
            setNoopFunctions()
        end
    end

    Framework.ClientReady = true
    Framework.Log('info', 'Client bridge ready')
end)

function Framework.WaitForClientReady()
    while not Framework.ClientReady do
        Wait(10)
    end
end
