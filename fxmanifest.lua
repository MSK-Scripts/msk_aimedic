fx_version 'cerulean'
games { 'gta5' }

author 'Musiker15 - MSK Scripts'
name 'msk_aimedic'
description 'AI Medic NPC (ESX & QBCore)'
version '1.7.0'

lua54 'yes'

shared_scripts {
	'@msk_core/import.lua',
	'config.lua',
	'translation.lua'
}

client_scripts {
	'client.lua'
}

server_scripts {
	'server.lua'
}

-- Eagerly load the msk_core modules this resource relies on (optional, speeds up first access)
msk_core 'Callback'
msk_core 'Request'
msk_core 'Math'

dependencies {
	'msk_core',
}
