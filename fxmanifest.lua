fx_version 'cerulean'
games { 'gta5' }

author 'Musiker15 - MSK Scripts'
name 'msk_aimedic'
description 'AI Medic NPC'
version '1.5.4'

lua54 'yes'

shared_scripts {
	'@es_extended/imports.lua',
	'config.lua',
	'translation.lua'
}

client_scripts {
	'client.lua'
}

server_scripts {
	'server.lua'
}

dependencies {
	'es_extended',
}