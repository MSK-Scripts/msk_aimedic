-- Notifications, TextUI and progress bars use the table forms of msk_core 4.1.0.
-- An older msk_core shows broken notifications, so say it loudly on start.
MSK.Check.Dependency('msk_core', '4.1.0', true)

local webHookLink = "INSERT DISCORD WEBHOOK LINK HERE"

----------------------------------------------------------------
-- Framework setup (ESX & QBCore)
----------------------------------------------------------------
local Framework = (GetResourceState('es_extended') ~= 'missing' and 'ESX')
    or (GetResourceState('qb-core') ~= 'missing' and 'QBCore')
    or 'ESX'

local ESX, QBCore
if Framework == 'ESX' then
    ESX = exports['es_extended']:getSharedObject()
elseif Framework == 'QBCore' then
    QBCore = exports['qb-core']:GetCoreObject()
end

local payCooldown = {} -- [src] = os.time() of the last successful revive payment

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
local function countOnlineMedics()
    local count = 0

    if Framework == 'ESX' then
        for _, job in ipairs(Config.Jobs.jobs) do
            local players = ESX.GetExtendedPlayers('job', job)
            count = count + (players and #players or 0)
        end
    elseif Framework == 'QBCore' then
        for _, Player in pairs(QBCore.Functions.GetQBPlayers()) do
            local jobName = Player.PlayerData.job.name
            for _, job in ipairs(Config.Jobs.jobs) do
                if job == jobName then
                    count = count + 1
                    break
                end
            end
        end
    end

    return count
end

-- Returns: cash, bank, playerObject (or nil if the player is not loaded)
local function getPlayerMoney(src)
    if Framework == 'ESX' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then return nil end
        return xPlayer.getAccount('money').money, xPlayer.getAccount('bank').money, xPlayer
    elseif Framework == 'QBCore' then
        local Player = QBCore.Functions.GetPlayer(src)
        if not Player then return nil end
        return Player.PlayerData.money['cash'], Player.PlayerData.money['bank'], Player
    end
end

local function removePlayerMoney(player, accountKey, amount)
    if Framework == 'ESX' then
        player.removeAccountMoney(accountKey == 'bank' and 'bank' or 'money', amount)
    elseif Framework == 'QBCore' then
        player.Functions.RemoveMoney(accountKey == 'bank' and 'bank' or 'cash', amount, 'msk_aimedic')
    end
end

local function getPlayerName(src)
    if Framework == 'ESX' then
        local xPlayer = ESX.GetPlayerFromId(src)
        return xPlayer and xPlayer.getName() or ('Player ' .. src)
    elseif Framework == 'QBCore' then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            local ci = Player.PlayerData.charinfo
            return ('%s %s'):format(ci.firstname, ci.lastname)
        end
    end
    return 'Player ' .. src
end

local function sendDiscordLog(src)
    if not Config.DiscordLog then return end

    local content = {{
        ["title"] = "MSK AI Medic",
        ["description"] = Translation[Config.Locale]['discord_webhook']:format(getPlayerName(src), src),
        ["color"] = Config.botColor,
        ["footer"] = {
            ["text"] = "© MSK Scripts • " .. os.date("%d/%m/%Y %H:%M:%S"),
            ["icon_url"] = Config.botAvatar
        }
    }}

    PerformHttpRequest(webHookLink, function() end, 'POST', json.encode({
        username = Config.botName,
        embeds = content,
        avatar_url = Config.botAvatar
    }), {
        ['Content-Type'] = 'application/json'
    })
end

----------------------------------------------------------------
-- Broadcast online medic count to everyone
----------------------------------------------------------------
CreateThread(function()
    while true do
        TriggerClientEvent('msk_aimedic:refreshMedics', -1, countOnlineMedics())
        Wait(10000)
    end
end)

AddEventHandler('playerDropped', function()
    payCooldown[source] = nil
end)

----------------------------------------------------------------
-- Callbacks (server-authoritative)
----------------------------------------------------------------
MSK.Callback.Register('msk_aimedic:getOnlineMedics', function(src, cb)
    cb(countOnlineMedics())
end)

MSK.Callback.Register('msk_aimedic:canAfford', function(src, cb)
    local cash, bank = getPlayerMoney(src)
    if not cash then return cb(false) end
    cb((cash >= Config.RevivePrice) or (bank >= Config.RevivePrice))
end)

MSK.Callback.Register('msk_aimedic:payRevive', function(src, cb)
    -- S2: anti-spam cooldown
    local now = os.time()
    if payCooldown[src] and (now - payCooldown[src]) < 5 then
        return cb(false)
    end

    -- A real medic must not be online
    if countOnlineMedics() > Config.Jobs.amount then
        return cb(false)
    end

    -- R4: server-side funds validation (cash first, then bank)
    local cash, bank, player = getPlayerMoney(src)
    if not player then return cb(false) end

    local accountKey
    if cash >= Config.RevivePrice then
        accountKey = 'money'
    elseif bank >= Config.RevivePrice then
        accountKey = 'bank'
    else
        return cb(false)
    end

    removePlayerMoney(player, accountKey, Config.RevivePrice)

    if Config.Society.enable then
        local societyName = (Config.Society.account or ''):gsub('^society_', '')
        exports.msk_core:SocietyAddMoney(societyName, Config.RevivePrice)
    end

    payCooldown[src] = now
    sendDiscordLog(src)

    cb(true)
end)

----------------------------------------------------------------
-- Version check
----------------------------------------------------------------
if Config.VersionChecker then
    exports.msk_core:CheckVersion({
        author = 'MSK-Scripts',
        name = 'msk_aimedic',
        print = true,
    })
end
