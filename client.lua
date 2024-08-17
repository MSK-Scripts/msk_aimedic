isDead, OnlineMedics = false, 10
isControlPressed = (Config.VisnAre or Config.OSPAmbulance) and IsDisabledControlPressed or IsControlJustPressed
canRevive = true
task, medic = {}, {}

refreshOnlineMedics = function()
    ESX.TriggerServerCallback('msk_aimedic:getOnlineMedics', function(medics)
        OnlineMedics = medics
    end)
end
refreshOnlineMedics()

toggleCanRevive = function(toggle)
    canRevive = toggle
end
exports('toggleCanRevive', toggleCanRevive)
RegisterNetEvent('msk_aimedic:canRevive', toggleCanRevive)

getCanCallMedic = function()
    return canRevive
end
exports('getCanCallMedic', getCanCallMedic)

getIsDead = function()
    local isPlayerDead = isDead

    if Config.VisnAre then
        local healthBuffer = exports.visn_are:GetHealthBuffer()
        isPlayerDead = healthBuffer.unconscious
    end

    if Config.OSPAmbulance then
        local data = exports.osp_ambulance:GetAmbulanceData(GetPlayerServerId(PlayerId()))
        isPlayerDead = data.isDead or data.inLastStand
    end

    isDead = isPlayerDead

    return isPlayerDead
end

AddEventHandler('esx:onPlayerDeath', function(data) 
    isDead = true
    medic.triedToRevive = false
end)

AddEventHandler('playerSpawned', function()
    isDead = false
    medic.called = false
    medic.onRoad = false

    leaveTarget()
end)

RegisterNetEvent('msk_aimedic:refreshMedics', function(medics)
    OnlineMedics = medics
end)

if Config.AbortMedic.enable then
    RegisterCommand(Config.AbortMedic.command, function(source, args, raw)
        abortAIMedic()
    end)
    RegisterKeyMapping(Config.AbortMedic.command, 'Abort AI Medic', 'keyboard', Config.AbortMedic.hotkey)
end

CreateThread(function()
	while true do
		local sleep = 500

		if getIsDead() and OnlineMedics <= Config.Jobs.amount and hasEnoughMoney() and getCanCallMedic() then
            if not medic.called and not medic.triedToRevive then
                sleep = 0
                DrawGenericText(Translation[Config.Locale]['input']:format(Config.Hotkey.label, comma(Config.RevivePrice)))

                if isControlPressed(0, Config.Hotkey.key) then
                    medic.called = true
                    callAIMedic()
                end
            end
		end

		Wait(sleep)
	end
end)

getStartingLocation = function(coords)
    local found, spawnPos, spawnHeading = GetClosestVehicleNodeWithHeading(coords.x + math.random(-Config.SpawnRadius, Config.SpawnRadius), coords.y + math.random(-Config.SpawnRadius, Config.SpawnRadius), coords.z, 0, 3.0, 0)
    return found, spawnPos, spawnHeading
end

getStoppingLocation = function(coords)
    local _, nCoords = GetClosestVehicleNode(coords.x, coords.y, coords.z, 1, 3.0, 0)
    return nCoords
end

getVehNodeType = function(coords)
    local _, _, flags = GetVehicleNodeProperties(coords.x, coords.y, coords.z)
    return flags
end

callAIMedic = function()
    local driverHash = GetHashKey(Config.Medic.pedmodel)
    local vehHash = GetHashKey(Config.Medic.vehmodel)

    loadModel(driverHash)
    loadModel(vehHash)

    local playerCoords = GetEntityCoords(PlayerPedId())
    spawnVehicle(playerCoords, driverHash, vehHash)
    startDriveToPlayer(playerCoords)
end
exports('callAIMedic', callAIMedic)

spawnVehicle = function(coords, driverHash, vehHash)
    local found, coords, heading = getStartingLocation(coords)

    if found then
        task.vehicle = CreateVehicle(vehHash, vector3(coords.x, coords.y, coords.z), heading, true, false)
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

        task.blip = AddBlipForEntity(task.vehicle)
        SetBlipSprite(task.blip, 56)
        SetBlipFlashes(task.blip, true)
        SetBlipColour(task.blip, 1)
    else
        spawnVehicle(coords, driverHash, vehHash)
    end
end

startDriveToPlayer = function(playerCoords)
    local toCoords = getStoppingLocation(playerCoords)

    TaskVehicleDriveToCoordLongrange(task.npc, task.vehicle, toCoords.x, toCoords.y, toCoords.z, 17.0, Config.DrivingStyle, 5.0)
    SetPedKeepTask(task.npc, true)
    AdvancedNotification(Translation[Config.Locale]['medic_send']:format(Config.Medic.name), 'Los Santos', 'Medical Department', 'CHAR_CALL911')
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

    while medic.onRoad do
        Wait(500)
        local distance = #(playerCoords - GetEntityCoords(task.npc))
        local npcStopRunning = false
        TaskGoToCoordAnyMeans(task.npc, playerCoords, 2.0, 0, false, 786475, 1.0)

        if distance <= 10.0 and not npcStopRunning then -- stops ai from sprinting when close
            TaskGoToCoordAnyMeans(task.npc, playerCoords, 1.0, 0, false, 786475, 1.0)
            npcStopRunning = true
        end

        if distance <= 2.0 then
            TaskTurnPedToFaceCoord(task.npc, playerCoords, -1)
            Wait(1000)

            loadAnimDict("mini@cpr@char_a@cpr_str")
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
                        AdvancedNotification(Translation[Config.Locale]['revive_fail']:format(Config.Medic.name), 'Los Santos', 'Medical Department', 'CHAR_CALL911')
                        leaveTarget()
                    else
                        tryAgain = tryAgain - 1

                        if tryAgain == 0 then
                            medic.triedToRevive = true
                            ClearPedTasks(task.npc)
                            AdvancedNotification(Translation[Config.Locale]['revive_fail_after_x_tries']:format(Config.Medic.name, Config.ReviveChance.howOften), 'Los Santos', 'Medical Department', 'CHAR_CALL911')
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

    AdvancedNotification(Translation[Config.Locale]['abort'], 'Los Santos', 'Medical Department', 'CHAR_CALL911')
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
        local sleep = 1

        DrawGenericText(Translation[Config.Locale]['input_abort']:format(Config.AbortMedic.hotkey))

        Wait(sleep)
    end
end

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

AdvancedNotification = function(text, title, subtitle, icon, flash, icontype)
    if not flash then flash = true end
    if not icontype then icontype = 1 end
    if not icon then icon = 'CHAR_HUMANDEFAULT' end

    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandThefeedPostMessagetext(icon, icon, flash, icontype, title, subtitle)
	EndTextCommandThefeedPostTicker(false, true)
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