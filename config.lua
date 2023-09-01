Config = {}
----------------------------------------------------------------
Config.Locale = 'de'
Config.VersionChecker = true
----------------------------------------------------------------
Config.Hotkey = {key = 38, label = 'E'}
Config.SpawnRadius = 150 -- default: 150 meters
Config.DrivingStyle = 786475 -- default: 786475 // https://vespura.com/fivem/drivingstyle/
----------------------------------------------------------------
Config.ReviveDuration = 10 -- in seconds // default: 10 seconds

Config.ReviveChance = {
    enable = true, -- Set false that you always get revived
    chance = 50, -- Percent to get revived

    tryagain = false, -- Set to true if the NPC should try it again if he failed
    howOften = 3, -- If NPC failed to revive the player then he tries up to 3 times more
}
----------------------------------------------------------------
Config.Jobs = {
    amount = 0, 
    jobs = {
        'ambulance',
    }
}
----------------------------------------------------------------
Config.Medic = {
    npcName = 'Doc. Holiday', 
    pedmodel = 's_m_m_doctor_01', 
    vehmodel = 'ambulance',
}
----------------------------------------------------------------
Config.ProgressBar = function()
    exports.msk_core:ProgressStart(10000, 'Du wirst nun wiederbelebt...')
end

Config.ReviveTrigger = function()
    TriggerEvent('esx_ambulancejob:revive')
    -- TriggerEvent('visn_are:resetHealthBuffer')
end