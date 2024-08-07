local isDead, OnlineMedics, medicCalled, medicOnRoad, triedToRevive, wasRevived = false, 5, false, false, false, false
local taskVehicle, taskNPC, taskBlip = nil, nil, nil
local isControlPressed = (Config.VisnAre or Config.OSPAmbulance) and IsDisabledControlPressed or IsControlJustPressed
local canRevive = true

toggleCanRevive = function(toggle)
    canRevive = toggle
end
exports('toggleCanRevive', toggleCanRevive)
RegisterNetEvent('msk_aimedic:canRevive', toggleCanRevive)

AddEventHandler('esx:onPlayerDeath', function(data) 
    isDead = true
    triedToRevive = false
end)

AddEventHandler('playerSpawned', function()
    isDead = false
    medicCalled = false
    medicOnRoad = false

    if wasRevived then 
        wasRevived = false
        TriggerServerEvent('msk_aimedic:removeMoney') 
    end

    leaveTarget()
end)

RegisterNetEvent('msk_aimedic:refreshMedics', function(medics)
    OnlineMedics = medics
end)

CreateThread(function()
	while true do
		local sleep = 500

		if isDead and OnlineMedics <= Config.Jobs.amount and hasEnoughMoney() then
			sleep = 0

            if not medicCalled and not triedToRevive and canRevive then
                drawGenericText(Translation[Config.Locale]['input']:format(Config.Hotkey.label, comma(Config.RevivePrice)))

                if isControlPressed(0, Config.Hotkey.key) then
                    medicCalled = true
                    advancedNotification(Translation[Config.Locale]['medic_send']:format(Config.Medic.npcName), 'Los Santos', 'Medical Department', 'CHAR_CALL911')
                    startAIMedic()
                end
            end
		end

		Wait(sleep)
	end
end)

startAIMedic = function()
    local driverhash = GetHashKey(Config.Medic.pedmodel)
    local vehhash = GetHashKey(Config.Medic.vehmodel)

    loadModel(driverhash)
    loadModel(vehhash)

    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    spawnVehicle(playerCoords, driverhash, vehhash)

    local _, closestRoad, closestRoad2 = GetClosestRoad(playerCoords.x, playerCoords.y, playerCoords.z , 0, 0, false)
    npcVehicleToPlayer(closestRoad, taskVehicle, taskNPC, vehhash, playerPed, playerCoords)
end

spawnVehicle = function(coords, driverhash, vehhash)
    local found, spawnPos, spawnHeading = GetClosestVehicleNodeWithHeading(coords.x + math.random(-Config.SpawnRadius, Config.SpawnRadius), coords.y + math.random(-Config.SpawnRadius, Config.SpawnRadius), coords.z, 0, 3, 0)

    if found then
        taskVehicle = CreateVehicle(vehhash, spawnPos, spawnHeading, true, false)
        ClearAreaOfVehicles(GetEntityCoords(taskVehicle), 5000, false, false, false, false, false)
        SetVehicleOnGroundProperly(taskVehicle)
        SetVehicleSiren(taskVehicle, true)
        SetVehicleUndriveable(taskVehicle, true)
        SetVehicleDoorsLockedForNonScriptPlayers(taskVehicle, true)

        taskNPC = CreatePedInsideVehicle(taskVehicle, 26, driverhash, -1, true, false)
        SetBlockingOfNonTemporaryEvents(taskNPC, true)

        taskBlip = AddBlipForEntity(taskVehicle)
        SetBlipFlashes(taskBlip, true)
        SetBlipColour(taskBlip, 5)
    else
        spawnVehicle(coords, driverhash, vehhash)
    end
end

npcVehicleToPlayer = function(coords, vehicle, npc, vehhash, target, targetCoords)
    TaskVehicleDriveToCoord(npc, vehicle, coords.x, coords.y, coords.z, 17.0, 0, vehhash, Config.DrivingStyle, 1.0, true)
    medicOnRoad = true

    while medicOnRoad do
        Wait(500)
        local vehicleCoords = GetEntityCoords(vehicle)
        local distance = #(coords - vehicleCoords)

        if distance < 20.0 then
            TaskVehicleTempAction(npc, vehicle, 27, 6000)
            SetVehicleUndriveable(vehicle, true)
            SetVehicleDoorsLockedForNonScriptPlayers(vehicle, true)
            npcToPlayer(target, targetCoords, vehicle, vehicleCoords, npc)
        end
    end
end

npcToPlayer = function(target, targetCoords, vehicle, vehicleCoords, npc)
    local tryAgain = Config.ReviveChance.howOften

    while medicOnRoad do
        Wait(500)
        local distance = #(targetCoords - GetEntityCoords(npc))
        local npcStopRunning = false
        TaskGoToCoordAnyMeans(npc, targetCoords, 2.0, 0, false, 786475, 1.0)

        if distance <= 10.0 and not npcStopRunning then -- stops ai from sprinting when close
            TaskGoToCoordAnyMeans(npc, targetCoords, 1.0, 0, false, 786475, 1.0)
            npcStopRunning = true
        end

        if distance <= 2.0 then
            TaskTurnPedToFaceCoord(npc, targetCoords, -1)
            Wait(1000)

            loadAnimDict("mini@cpr@char_a@cpr_str")
            TaskPlayAnim(npc, "mini@cpr@char_a@cpr_str", "cpr_pumpchest", 1.0, 1.0, -1, 9, 1.0, 0, 0, 0)
            Config.ProgressBar()

            Wait(Config.ReviveDuration * 1000)

            if not Config.ReviveChance.enable then
                wasRevived = true
                Config.ReviveTrigger()
                ClearPedTasks(npc)
                advancedNotification(Translation[Config.Locale]['was_revived']:format(Config.Medic.npcName), 'Los Santos', 'Medical Department', 'CHAR_CALL911')
                leaveTarget()
            else
                local chance = math.random(100)
                
                if chance <= Config.ReviveChance.chance then
                    wasRevived = true
                    Config.ReviveTrigger()
                    ClearPedTasks(npc)
                    advancedNotification(Translation[Config.Locale]['was_revived']:format(Config.Medic.npcName), 'Los Santos', 'Medical Department', 'CHAR_CALL911')
                    leaveTarget()
                else
                    if not Config.ReviveChance.tryagain then
                        triedToRevive = true
                        ClearPedTasks(npc)
                        advancedNotification(Translation[Config.Locale]['revive_fail']:format(Config.Medic.npcName), 'Los Santos', 'Medical Department', 'CHAR_CALL911')
                        leaveTarget()
                    else
                        tryAgain = tryAgain - 1

                        if tryAgain == 0 then
                            triedToRevive = true
                            ClearPedTasks(npc)
                            advancedNotification(Translation[Config.Locale]['revive_fail_after_x_tries']:format(Config.Medic.npcName, Config.ReviveChance.howOften), 'Los Santos', 'Medical Department', 'CHAR_CALL911')
                            leaveTarget()
                        end
                    end
                end
            end
        end
    end
end

leaveTarget = function()
    medicCalled = false
    medicOnRoad = false

    local blip, vehicle, npc = taskBlip, taskVehicle, taskNPC
    taskBlip = nil
    taskVehicle = nil
    taskNPC = nil

	if blip then RemoveBlip(blip) end
    if vehicle and npc then
        SetVehicleSiren(vehicle, false)
        TaskVehicleDriveWander(npc, vehicle, 17.0, Config.DrivingStyle)
        Wait(10000)
        SetPedAsNoLongerNeeded(npc)
        SetEntityAsNoLongerNeeded(vehicle)
        DeleteEntity(npc)
        DeleteEntity(vehicle)
    end
end

refreshOnlineMedics = function()
    ESX.TriggerServerCallback('msk_aimedic:getOnlineMedics', function(medics)
        OnlineMedics = medics
    end)
end
refreshOnlineMedics()

loadAnimDict = function(dict)
    if not HasAnimDictLoaded(dict) then
        RequestAnimDict(dict)

        while not HasAnimDictLoaded(dict) do
            Wait(1)
        end
    end
end

loadModel = function(modelHash)
    if not HasModelLoaded(modelHash) then
        RequestModel(modelHash)
    
        while not HasModelLoaded(modelHash) do
            Wait(1)
        end
    end
end

drawGenericText = function(text)
	SetTextColour(186, 186, 186, 255)
	SetTextFont(0)
	SetTextScale(0.34, 0.34)
	SetTextWrap(0.0, 1.0)
	SetTextCentre(true)
	SetTextDropshadow(0, 0, 0, 0, 255)
	SetTextEdge(1, 0, 0, 0, 205)
	SetTextEntry("STRING")
	AddTextComponentString(text)
	EndTextCommandDisplayText(0.5, 0.90)
end

advancedNotification = function(text, title, subtitle, icon, flash, icontype)
    if not flash then flash = true end
    if not icontype then icontype = 1 end
    if not icon then icon = 'CHAR_HUMANDEFAULT' end

    SetNotificationTextEntry('STRING')
    AddTextComponentString(text)
    SetNotificationMessage(icon, icon, flash, icontype, title, subtitle)
	DrawNotification(false, true)
end

hasEnoughMoney = function()
    local cash = getAccount('money').money
    local bank = getAccount('bank').money

    return cash >= Config.RevivePrice or bank >= Config.RevivePrice
end

getAccount = function(account)
    local player = ESX.GetPlayerData()

    for k, v in pairs(player.accounts) do
        if v.name == account then
            return v
        end
    end
    return false
end

comma = function(int, tag)
    if not tag then tag = '.' end
    local newInt = int

    while true do  
        newInt, k = string.gsub(newInt, "^(-?%d+)(%d%d%d)", '%1'..tag..'%2')

        if (k == 0) then
            break
        end
    end

    return newInt
end