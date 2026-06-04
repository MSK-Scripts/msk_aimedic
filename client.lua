-- Framework-agnostic (ESX & QBCore) - all framework access goes through msk_core / natives.
isDead = false       -- global: read/written by Config.ReviveTrigger
task, medic = {}, {} -- global: shared with Config.ReviveTrigger

local wasDead = false
local OnlineMedics = 10
local canAfford = false
local canRevive = true
local isControlPressed = (Config.VisnAre or Config.OSPAmbulance) and IsDisabledControlPressed or IsControlJustPressed

-- Forward declarations (functions reference each other)
local getIsDead, refreshAffordability, refreshOnlineMedics
local callAIMedic, spawnVehicle, startDriveToPlayer, startWalkToPlayer
local abortAIMedic, leaveTarget, drawAbort
local getStartingLocation, getStoppingLocation, DrawGenericText

----------------------------------------------------------------
-- State / framework helpers
----------------------------------------------------------------
getIsDead = function()
    local dead = IsPlayerDead(PlayerId()) or IsEntityDead(PlayerPedId())

    if Config.VisnAre then
        local ok, healthBuffer = pcall(function() return exports.visn_are:GetHealthBuffer() end)
        if ok and healthBuffer then dead = healthBuffer.unconscious end
    elseif Config.OSPAmbulance then
        local ok, data = pcall(function() return exports.osp_ambulance:GetAmbulanceData(GetPlayerServerId(PlayerId())) end)
        if ok and data then dead = data.isDead or data.inLastStand end
    end

    return dead
end

refreshAffordability = function()
    local ok = MSK.Callback.TriggerCallback('msk_aimedic:canAfford')
    canAfford = ok and true or false
end

refreshOnlineMedics = function()
    CreateThread(function()
        local medics = MSK.Callback.TriggerCallback('msk_aimedic:getOnlineMedics')
        if medics ~= nil then OnlineMedics = medics end
    end)
end
refreshOnlineMedics()

local toggleCanRevive = function(toggle)
    canRevive = toggle
end
exports('toggleCanRevive', toggleCanRevive)
RegisterNetEvent('msk_aimedic:canRevive', toggleCanRevive)

local getCanCallMedic = function()
    return canRevive
end
exports('getCanCallMedic', getCanCallMedic)

RegisterNetEvent('msk_aimedic:refreshMedics', function(medics)
    OnlineMedics = medics
end)

AddEventHandler('playerSpawned', function()
    isDead = false
    wasDead = false
    medic.called = false
    medic.onRoad = false

    leaveTarget()
end)

if Config.AbortMedic.enable then
    RegisterCommand(Config.AbortMedic.command, function()
        abortAIMedic()
    end)
    RegisterKeyMapping(Config.AbortMedic.command, 'Abort AI Medic', 'keyboard', Config.AbortMedic.hotkey)
end

----------------------------------------------------------------
-- Main loop: offer the AI medic while dead and no real medic is online
----------------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 500
        isDead = getIsDead()

        if isDead and not wasDead then
            -- transition: the player just died -> reset state & refresh affordability
            medic.called = false
            medic.triedToRevive = false
            refreshAffordability()
        end
        wasDead = isDead

        if isDead and OnlineMedics <= Config.Jobs.amount and canAfford and canRevive then
            if not medic.called and not medic.triedToRevive then
                sleep = 0
                DrawGenericText(Translation[Config.Locale]['input']:format(Config.Hotkey.label, MSK.Math.Comma(Config.RevivePrice)))

                if isControlPressed(0, Config.Hotkey.key) then
                    medic.called = true
                    callAIMedic()
                end
            end
        end

        Wait(sleep)
    end
end)

----------------------------------------------------------------
-- Spawn & drive
----------------------------------------------------------------
getStartingLocation = function(coords)
    local found, spawnPos, spawnHeading = GetClosestVehicleNodeWithHeading(coords.x + math.random(-Config.SpawnRadius, Config.SpawnRadius), coords.y + math.random(-Config.SpawnRadius, Config.SpawnRadius), coords.z, 0, 3.0, 0)
    return found, spawnPos, spawnHeading
end

getStoppingLocation = function(coords)
    local _, nCoords = GetClosestVehicleNode(coords.x, coords.y, coords.z, 1, 3.0, 0)
    return nCoords
end

callAIMedic = function()
    local driverHash = joaat(Config.Medic.pedmodel)
    local vehHash = joaat(Config.Medic.vehmodel)

    MSK.Request.Model(driverHash)
    MSK.Request.Model(vehHash)

    local playerCoords = GetEntityCoords(PlayerPedId())

    if not spawnVehicle(playerCoords, driverHash, vehHash) then
        -- No vehicle node found near the player (e.g. ocean/mountains)
        SetModelAsNoLongerNeeded(driverHash)
        SetModelAsNoLongerNeeded(vehHash)
        medic.called = false
        exports.msk_core:AdvancedNotification(Translation[Config.Locale]['revive_fail']:format(Config.Medic.name), 'Los Santos', 'Medical Department', 'CHAR_CALL911')
        return
    end

    startDriveToPlayer(playerCoords)
end
exports('callAIMedic', callAIMedic)

spawnVehicle = function(coords, driverHash, vehHash)
    local found, spawnCoords, heading
    local attempts = 0

    -- B1 fix: loop with Wait instead of unbounded recursion
    repeat
        found, spawnCoords, heading = getStartingLocation(coords)
        if not found then
            attempts = attempts + 1
            Wait(100)
        end
    until found or attempts >= 50

    if not found then return false end

    task.vehicle = CreateVehicle(vehHash, vector3(spawnCoords.x, spawnCoords.y, spawnCoords.z), heading, true, false)
    SetVehicleOnGroundProperly(task.vehicle)
    SetVehicleEngineOn(task.vehicle, true, true, false)
    SetVehicleUndriveable(task.vehicle, true)
    SetVehicleFuelLevel(task.vehicle, 100.0)
    DecorSetFloat(task.vehicle, '_FUEL_LEVEL', 100.0)
    SetVehicleSiren(task.vehicle, true)
    SetVehicleDoorsLockedForNonScriptPlayers(task.vehicle, true)
    for i = 0, 5 do
        SetVehicleDoorCanBreak(task.vehicle, i, false)
    end
    SetEntityAsMissionEntity(task.vehicle, true, true)

    task.npc = CreatePedInsideVehicle(task.vehicle, 26, driverHash, -1, true, false)
    SetBlockingOfNonTemporaryEvents(task.npc, true)
    SetDriverAbility(task.npc, 1.0)
    SetEntityAsMissionEntity(task.npc, true, true)

    -- R1 fix: release the models now that the entities exist
    SetModelAsNoLongerNeeded(driverHash)
    SetModelAsNoLongerNeeded(vehHash)

    task.blip = AddBlipForEntity(task.vehicle)
    SetBlipSprite(task.blip, 56)
    SetBlipFlashes(task.blip, true)
    SetBlipColour(task.blip, 1)

    return true
end

startDriveToPlayer = function(playerCoords)
    local toCoords = getStoppingLocation(playerCoords)

    TaskVehicleDriveToCoordLongrange(task.npc, task.vehicle, toCoords.x, toCoords.y, toCoords.z, 17.0, Config.DrivingStyle, 5.0)
    SetPedKeepTask(task.npc, true)
    exports.msk_core:AdvancedNotification(Translation[Config.Locale]['medic_send']:format(Config.Medic.name), 'Los Santos', 'Medical Department', 'CHAR_CALL911')
    medic.onRoad = true
    if Config.AbortMedic.enable then CreateThread(drawAbort) end

    while medic.onRoad do
        Wait(500)
        if medic.canceled then return end
        local vehicleCoords = GetEntityCoords(task.vehicle)
        local distance = #(toCoords - vehicleCoords)

        if distance < 10.0 then
            startWalkToPlayer(playerCoords)
        end
    end
end

startWalkToPlayer = function(playerCoords)
    local tryAgain = Config.ReviveChance.howOften
    local npcStopRunning = false -- B2 fix: declared outside the loop so it persists

    while medic.onRoad do
        Wait(500)
        if medic.canceled then return end
        local distance = #(playerCoords - GetEntityCoords(task.npc))
        TaskGoToCoordAnyMeans(task.npc, playerCoords, 2.0, 0, false, 786475, 1.0)

        if distance <= 10.0 and not npcStopRunning then -- stops ai from sprinting when close
            TaskGoToCoordAnyMeans(task.npc, playerCoords, 1.0, 0, false, 786475, 1.0)
            npcStopRunning = true
        end

        if distance <= 2.0 then
            TaskTurnPedToFaceCoord(task.npc, playerCoords, -1)
            Wait(1000)

            MSK.Request.AnimDict("mini@cpr@char_a@cpr_str")
            TaskPlayAnim(task.npc, "mini@cpr@char_a@cpr_str", "cpr_pumpchest", 1.0, 1.0, -1, 9, 1.0, 0, 0, 0)
            Config.ProgressBar()

            Wait(Config.ReviveDuration * 1000)

            if not Config.ReviveChance.enable then
                ClearPedTasks(task.npc)
                Config.ReviveTrigger()
                leaveTarget()
            else
                local chance = math.random(100)

                if chance <= Config.ReviveChance.chance then
                    ClearPedTasks(task.npc)
                    Config.ReviveTrigger()
                    leaveTarget()
                else
                    if not Config.ReviveChance.tryagain then
                        medic.triedToRevive = true
                        ClearPedTasks(task.npc)
                        exports.msk_core:AdvancedNotification(Translation[Config.Locale]['revive_fail']:format(Config.Medic.name), 'Los Santos', 'Medical Department', 'CHAR_CALL911')
                        leaveTarget()
                    else
                        tryAgain = tryAgain - 1

                        if tryAgain == 0 then
                            medic.triedToRevive = true
                            ClearPedTasks(task.npc)
                            exports.msk_core:AdvancedNotification(Translation[Config.Locale]['revive_fail_after_x_tries']:format(Config.Medic.name, Config.ReviveChance.howOften), 'Los Santos', 'Medical Department', 'CHAR_CALL911')
                            leaveTarget()
                        end
                    end
                end
            end
        end
    end
end

abortAIMedic = function()
    if not medic.called then return end
    if not medic.onRoad then return end
    if medic.finished then return end
    medic.canceled = true

    exports.msk_core:AdvancedNotification(Translation[Config.Locale]['abort'], 'Los Santos', 'Medical Department', 'CHAR_CALL911')
    leaveTarget()
end

leaveTarget = function()
    local blip, vehicle, npc = task.blip, task.vehicle, task.npc
    task = {}
    medic = {}

    if blip then RemoveBlip(blip) end
    if vehicle and npc then
        SetVehicleSiren(vehicle, false)
        TaskVehicleDriveWander(npc, vehicle, 17.0, Config.DrivingStyle)
        SetVehicleDoorsShut(vehicle, true)
        SetVehicleDoorsLockedForNonScriptPlayers(vehicle, 2)

        for i = 0, 5 do
            SetVehicleDoorCanBreak(vehicle, i, false)
        end

        Wait(10000)

        SetPedAsNoLongerNeeded(npc)
        SetEntityAsNoLongerNeeded(vehicle)
        DeleteEntity(npc)
        DeleteEntity(vehicle)
    end
end

drawAbort = function()
    while medic.onRoad and not medic.canceled and not medic.finished do
        DrawGenericText(Translation[Config.Locale]['input_abort']:format(Config.AbortMedic.hotkey))
        Wait(1)
    end
end

----------------------------------------------------------------
-- UI helper
----------------------------------------------------------------
DrawGenericText = function(text)
    SetTextColour(255, 255, 255, 255)
    SetTextFont(0)
    SetTextScale(0.34, 0.34)
    SetTextWrap(0.0, 1.0)
    SetTextCentre(true)
    SetTextDropshadow(0, 0, 0, 0, 255)
    SetTextEdge(1, 0, 0, 0, 205)
    SetTextOutline()
    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.50, 0.90)
end

----------------------------------------------------------------
-- R3 fix: clean up the NPC/vehicle if the resource stops mid-task
----------------------------------------------------------------
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if task.blip then RemoveBlip(task.blip) end
    if task.npc and DoesEntityExist(task.npc) then DeleteEntity(task.npc) end
    if task.vehicle and DoesEntityExist(task.vehicle) then DeleteEntity(task.vehicle) end
end)
