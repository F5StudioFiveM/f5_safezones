local Server = SafezoneServer
Server.Players = Server.Players or {}
local Players = Server.Players

local POSITION_TOLERANCE = 5.0

local function isPointInPolygonServer(x, y, points)
    local inside = false
    local n = #points
    local p1x, p1y = points[1].x, points[1].y

    for i = 1, n do
        local p2x, p2y = points[i % n + 1].x, points[i % n + 1].y

        if ((p1y > y) ~= (p2y > y)) and (x < (p2x - p1x) * (y - p1y) / (p2y - p1y) + p1x) then
            inside = not inside
        end

        p1x, p1y = p2x, p2y
    end

    return inside
end

local function isPlayerActuallyInZone(playerCoords, zone)
    if not playerCoords or not zone then
        return false
    end

    if zone.type == 'circle' then
        if not zone.coords then
            return false
        end

        local dx = playerCoords.x - zone.coords.x
        local dy = playerCoords.y - zone.coords.y
        local dist2d = math.sqrt(dx * dx + dy * dy)
        local radius = zone.radius or 50.0

        if dist2d > (radius + POSITION_TOLERANCE) then
            return false
        end

        if not zone.infiniteHeight then
            local minZ = zone.minZ or (zone.coords.z - 50)
            local maxZ = zone.maxZ or (zone.coords.z + 150)
            if playerCoords.z < (minZ - POSITION_TOLERANCE) or playerCoords.z > (maxZ + POSITION_TOLERANCE) then
                return false
            end
        end

        return true
    elseif zone.type == 'polygon' then
        if not zone.points or #zone.points < 3 then
            return false
        end

        if not zone.infiniteHeight then
            local minZ = zone.minZ or -200
            local maxZ = zone.maxZ or 800
            if playerCoords.z < (minZ - POSITION_TOLERANCE) or playerCoords.z > (maxZ + POSITION_TOLERANCE) then
                return false
            end
        end

        return isPointInPolygonServer(playerCoords.x, playerCoords.y, zone.points)
    end

    return false
end

local function getPlayerCoordsServer(src)
    local playerPed = GetPlayerPed(src)
    if not playerPed or playerPed == 0 or not DoesEntityExist(playerPed) then
        return nil
    end
    return GetEntityCoords(playerPed)
end

local function findAndVerifyZone(src, zoneName)
    local allZones = Server.Zones.GetAllZones()
    local matchedZone = nil

    for _, zone in ipairs(allZones) do
        if zone.name == zoneName and zone.isActive ~= false then
            matchedZone = zone
            break
        end
    end

    if not matchedZone then
        return false
    end

    local playerCoords = getPlayerCoordsServer(src)
    if not playerCoords then
        return false
    end

    if not isPlayerActuallyInZone(playerCoords, matchedZone) then
        local playerName = GetPlayerName(src) or 'Unknown'
        Log('NETWORK', 'Rejected safezone entry for %s (ID %d) in "%s" - position verification failed (%.1f, %.1f, %.1f)',
            playerName, src, zoneName, playerCoords.x, playerCoords.y, playerCoords.z)
        return false
    end

    return true
end

RegisterNetEvent('f5_safezones:playerEnteredZone', function(zoneName)
    local src = source

    if not zoneName or type(zoneName) ~= 'string' then
        return
    end

    if not findAndVerifyZone(src, zoneName) then
        TriggerClientEvent('f5_safezones:entryRejected', src)
        return
    end

    local previousZone = Server.playersInSafezones[src] and Server.playersInSafezones[src].zoneName or nil

    Server.playersInSafezones[src] = {
        zoneName = zoneName,
        enteredAt = os.time(),
        playerName = GetPlayerName(src)
    }

    local playerName = GetPlayerName(src)
    if previousZone and previousZone ~= zoneName then
        Log('PLAYER', '%s (ID %d) moved from "%s" to "%s"', playerName, src, previousZone, zoneName)
    else
        Log('PLAYER', '%s (ID %d) entered safezone "%s"', playerName, src, zoneName)
    end

    for playerId, info in pairs(Server.playersInSafezones) do
        if playerId ~= src and info.zoneName == zoneName then
            TriggerClientEvent('f5_safezones:playerEnteredSameZone', playerId, src)
        end
    end

    local playersInSameZone = {}
    for playerId, info in pairs(Server.playersInSafezones) do
        if playerId ~= src and info.zoneName == zoneName then
            table.insert(playersInSameZone, playerId)
        end
    end

    if #playersInSameZone > 0 then
        TriggerClientEvent('f5_safezones:receivePlayersInZone', src, playersInSameZone)
    end

    TriggerEvent('f5_safezones:playerEntered', src, zoneName)
end)

RegisterNetEvent('f5_safezones:playerExitedZone', function(zoneName)
    local src = source

    if Server.playersInSafezones[src] then
        local timeInZone = os.time() - Server.playersInSafezones[src].enteredAt
        local actualZoneName = Server.playersInSafezones[src].zoneName

        for playerId, info in pairs(Server.playersInSafezones) do
            if playerId ~= src and info.zoneName == actualZoneName then
                TriggerClientEvent('f5_safezones:playerLeftSameZone', playerId, src)
            end
        end

        Server.playersInSafezones[src] = nil

        local playerName = GetPlayerName(src)
        Log('PLAYER', '%s (ID %d) left safezone "%s" after %d second(s)', playerName, src, actualZoneName, timeInZone)

        TriggerEvent('f5_safezones:playerExited', src, actualZoneName, timeInZone)
    end
end)

RegisterNetEvent('f5_safezones:requestPlayersInZone', function(zoneName)
    local src = source

    if not zoneName or type(zoneName) ~= 'string' then
        return
    end

    local playersInZone = {}
    for playerId, info in pairs(Server.playersInSafezones) do
        if info.zoneName == zoneName and playerId ~= src then
            table.insert(playersInZone, playerId)
        end
    end

    TriggerClientEvent('f5_safezones:receivePlayersInZone', src, playersInZone)
end)

RegisterNetEvent('f5_safezones:syncCollisionResponse', function(targetPlayer, inSafezone)
    local src = source

    if inSafezone and Server.playersInSafezones[src] and Server.playersInSafezones[targetPlayer] then
        TriggerClientEvent('f5_safezones:applyCollisionSync', targetPlayer, src)
        TriggerClientEvent('f5_safezones:applyCollisionSync', src, targetPlayer)
    end
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    if Server.playersInSafezones[src] then
        local zoneName = Server.playersInSafezones[src].zoneName
        local timeInZone = os.time() - Server.playersInSafezones[src].enteredAt
        local playerName = Server.playersInSafezones[src].playerName or 'Unknown'

        for playerId, info in pairs(Server.playersInSafezones) do
            if playerId ~= src and info.zoneName == zoneName then
                TriggerClientEvent('f5_safezones:playerLeftSameZone', playerId, src)
            end
        end

        Server.playersInSafezones[src] = nil

        Log('PLAYER', '%s (ID %d) disconnected from "%s" after %d second(s) (%s)', playerName, src, zoneName,
            timeInZone, reason or 'No reason provided')
    end
end)

AddEventHandler('weaponDamageEvent', function(sender, data)
    if not data or not data.hitGlobalId then
        return
    end

    local victim = data.hitGlobalId
    local victimEntity = NetworkGetEntityFromNetworkId(victim)

    if not DoesEntityExist(victimEntity) then
        return
    end

    if IsPedAPlayer(victimEntity) then
        local victimPlayer = NetworkGetEntityOwner(victimEntity)
        if not victimPlayer then
            return
        end

        local victimServerId = victimPlayer
        local attackerServerId = sender

        if Server.playersInSafezones[victimServerId] or Server.playersInSafezones[attackerServerId] then
            data.willKill = false
            data.damageTime = 0
            data.localDamage = 0
            data.overrideDefaultDamage = true
            data.hasEntityBeenDamaged = false
            data.hasEntityDied = false

            CancelEvent()

            if Server.playersInSafezones[attackerServerId] then
                TriggerClientEvent('f5_safezones:showNotification', attackerServerId,
                    Translate('combat_disabled'), 'error')
            end

            Log('NETWORK', 'Prevented damage: %s -> %s with weapon %s',
                GetPlayerName(attackerServerId) or 'Unknown',
                GetPlayerName(victimServerId) or 'Unknown',
                data.weaponType or 'Unknown')
        end
    elseif GetEntityType(victimEntity) == 2 then
        local vehicle = victimEntity

        for i = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
            local ped = GetPedInVehicleSeat(vehicle, i)
            if ped and IsPedAPlayer(ped) then
                local player = NetworkGetEntityOwner(ped)
                if player and Server.playersInSafezones[player] then
                    data.willKill = false
                    data.damageTime = 0
                    data.localDamage = 0
                    data.overrideDefaultDamage = true
                    data.hasEntityBeenDamaged = false

                    CancelEvent()

                    TriggerClientEvent('f5_safezones:showNotification', sender,
                        Translate('vehicle_damage_disabled'), 'error')

                    break
                end
            end
        end
    end
end)

AddEventHandler('vehicleDamageEvent', function(vehicle, attacker, weapon, damage)
    if not vehicle or not DoesEntityExist(vehicle) then
        return
    end

    local cancelDamage = false

    for i = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        local ped = GetPedInVehicleSeat(vehicle, i)
        if ped and IsPedAPlayer(ped) then
            local player = NetworkGetEntityOwner(ped)
            if player and Server.playersInSafezones[player] then
                cancelDamage = true
                break
            end
        end
    end

    if cancelDamage then
        CancelEvent()

        if attacker and IsPedAPlayer(attacker) then
            local attackerPlayer = NetworkGetEntityOwner(attacker)
            if attackerPlayer then
                TriggerClientEvent('f5_safezones:showNotification', attackerPlayer,
                    Translate('vehicle_damage_disabled'), 'error')
            end
        end
    end
end)

AddEventHandler('explosionEvent', function(sender, ev)
    if not ev then
        return
    end

    local explosionCoords = vector3(ev.posX, ev.posY, ev.posZ)

    for playerId, info in pairs(Server.playersInSafezones) do
        local playerPed = GetPlayerPed(playerId)
        if DoesEntityExist(playerPed) then
            local playerCoords = GetEntityCoords(playerPed)
            local distance = #(playerCoords - explosionCoords)

            if distance < (Config.CollisionSystem.explosionRange or 100.0) then
                CancelEvent()

                TriggerClientEvent('f5_safezones:showNotification', sender,
                    Translate('explosions_disabled'), 'error')

                local senderName = GetPlayerName(sender) or 'Unknown'
                Log('NETWORK', 'Prevented explosion damage triggered by %s near a safezone', senderName)

                return
            end
        end
    end
end)

local VERIFY_INTERVAL = 5000

CreateThread(function()
    while true do
        Wait(VERIFY_INTERVAL)

        local toRemove = {}
        local allZones = nil

        for playerId, info in pairs(Server.playersInSafezones) do
            if not GetPlayerName(playerId) then
                toRemove[#toRemove + 1] = { id = playerId, reason = 'disconnected' }
            else
                local playerCoords = getPlayerCoordsServer(playerId)
                if not playerCoords then
                    toRemove[#toRemove + 1] = { id = playerId, reason = 'no_ped' }
                else
                    if not allZones then
                        allZones = Server.Zones.GetAllZones()
                    end

                    local matchedZone = nil
                    for _, zone in ipairs(allZones) do
                        if zone.name == info.zoneName and zone.isActive ~= false then
                            matchedZone = zone
                            break
                        end
                    end

                    if not matchedZone then
                        toRemove[#toRemove + 1] = { id = playerId, reason = 'zone_removed' }
                    elseif not isPlayerActuallyInZone(playerCoords, matchedZone) then
                        toRemove[#toRemove + 1] = { id = playerId, reason = 'outside_zone' }
                    end
                end
            end
        end

        for _, entry in ipairs(toRemove) do
            local playerId = entry.id
            local info = Server.playersInSafezones[playerId]
            if info then
                local zoneName = info.zoneName
                local playerName = info.playerName or GetPlayerName(playerId) or 'Unknown'

                for otherId, otherInfo in pairs(Server.playersInSafezones) do
                    if otherId ~= playerId and otherInfo.zoneName == zoneName then
                        TriggerClientEvent('f5_safezones:playerLeftSameZone', otherId, playerId)
                    end
                end

                Server.playersInSafezones[playerId] = nil

                if GetPlayerName(playerId) then
                    TriggerClientEvent('f5_safezones:forceExitZone', playerId)
                end

                Log('NETWORK', 'Removed %s (ID %d) from safezone "%s" via periodic verification (%s)',
                    playerName, playerId, zoneName, entry.reason)
            end
        end
    end
end)

function Players.IsPlayerInSafezone(playerId)
    return Server.playersInSafezones[playerId] ~= nil
end

function Players.GetPlayerSafezoneInfo(playerId)
    if Server.playersInSafezones[playerId] then
        return {
            zoneName = Server.playersInSafezones[playerId].zoneName,
            enteredAt = Server.playersInSafezones[playerId].enteredAt,
            timeInZone = os.time() - Server.playersInSafezones[playerId].enteredAt
        }
    end
    return nil
end

function Players.GetAllPlayersInSafezones()
    local players = {}
    for playerId, info in pairs(Server.playersInSafezones) do
        if GetPlayerName(playerId) then
            players[playerId] = {
                zoneName = info.zoneName,
                enteredAt = info.enteredAt,
                timeInZone = os.time() - info.enteredAt
            }
        end
    end
    return players
end

function Players.GetPlayersInSpecificZone(zoneName)
    local players = {}
    for playerId, info in pairs(Server.playersInSafezones) do
        if info.zoneName == zoneName and GetPlayerName(playerId) then
            table.insert(players, {
                playerId = playerId,
                playerName = info.playerName or GetPlayerName(playerId),
                enteredAt = info.enteredAt,
                timeInZone = os.time() - info.enteredAt
            })
        end
    end
    return players
end

function Players.GetAllSafezones()
    return Server.Zones.GetAllZones()
end

function IsPlayerInSafezone(playerId)
    return Players.IsPlayerInSafezone(playerId)
end

function GetPlayerSafezoneInfo(playerId)
    return Players.GetPlayerSafezoneInfo(playerId)
end

function GetAllPlayersInSafezones()
    return Players.GetAllPlayersInSafezones()
end

function GetPlayersInSpecificZone(zoneName)
    return Players.GetPlayersInSpecificZone(zoneName)
end

function GetAllSafezones()
    return Players.GetAllSafezones()
end

exports('IsPlayerInSafezone', IsPlayerInSafezone)
exports('GetPlayerSafezoneInfo', GetPlayerSafezoneInfo)
exports('GetAllPlayersInSafezones', GetAllPlayersInSafezones)
exports('GetPlayersInSpecificZone', GetPlayersInSpecificZone)
exports('GetAllSafezones', GetAllSafezones)
