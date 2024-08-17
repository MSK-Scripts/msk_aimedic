Config = {}
----------------------------------------------------------------
Config.Locale = 'de'
Config.VersionChecker = true
----------------------------------------------------------------
-- Add the Webhook Link in server.lua
Config.DiscordLog = true
Config.botColor = "6205745" -- https://www.mathsisfun.com/hexadecimal-decimal-colors.html
Config.botName = "MSK Scripts"
Config.botAvatar = "https://i.imgur.com/PizJGsh.png"
----------------------------------------------------------------
Config.VisnAre = GetResourceState("visn_are") ~= "missing"
Config.OSPAmbulance = GetResourceState("osp_ambulance") ~= "missing"
----------------------------------------------------------------
Config.Hotkey = {label = 'E', key = 38} -- G = 47

Config.AbortMedic = {
    enable = true,
    command = 'abortMedic',
    hotkey = 'X'
}
----------------------------------------------------------------
Config.SpawnRadius = 200.0 -- default: 200.0 meters // Do not set more than 200.0!
Config.DrivingStyle = 786475 -- default: 786475 // https://vespura.com/fivem/drivingstyle/

Config.RevivePrice = 5000 -- Price to get revived
Config.ReviveDuration = 10 -- in seconds // default: 10 seconds

Config.ReviveChance = {
    enable = true, -- Set false that you always get revived
    chance = 50, -- Percent to get revived

    tryagain = false, -- Set to true if the NPC should try it again if he failed
    howOften = 3, -- If NPC failed to revive the player then he tries up to 3 times more
}
----------------------------------------------------------------
-- You will need esx_addonaccount for that!
Config.Society = {
    enable = false, -- Set false if you don't want that the Config.RevivePrice will be added to a society account
    account = 'society_ambulance'
}

Config.Jobs = {
    amount = 0, 
    jobs = {
        'ambulance',
        'fire_department',
    }
}

Config.Medic = {
    name = 'Doc. Holiday', 
    pedmodel = 's_m_m_doctor_01', 
    vehmodel = 'ambulance',
}
----------------------------------------------------------------
Config.ProgressBar = function()
    exports.msk_core:Progressbar(Config.ReviveDuration * 1000, 'Du wirst nun wiederbelebt...')
end

Config.ReviveTrigger = function()
    isDead = false
    medic.called = false
    medic.onRoad = false
    medic.finished = true
    
    if Config.VisnAre then
        TriggerEvent('visn_are:resetHealthBuffer')
    elseif Config.OSPAmbulance then
        TriggerEvent('hospital:client:Revive')
    else
        TriggerEvent('esx_ambulancejob:revive')
    end

    AdvancedNotification(Translation[Config.Locale]['was_revived']:format(Config.Medic.name), 'Los Santos', 'Medical Department', 'CHAR_CALL911')
    TriggerServerEvent('msk_aimedic:removeMoney')
end