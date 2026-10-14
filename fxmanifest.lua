fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'statewide_security'
author 'Statewide Security'
description 'Standalone AI-driven private security job: patrols, site management, NPC incidents, AI dispatch and reporting'
version '1.0.0'

shared_scripts {
    'config.lua',
    'shared/utils.lua',
    'shared/incidents.lua',
    'shared/dialogue.lua',
}

server_scripts {
    'server/storage.lua',
    'server/main.lua',
    'server/patrol.lua',
    'server/incidents.lua',
    'server/reports.lua',
}

client_scripts {
    'client/main.lua',
    'client/nui.lua',
    'client/patrol.lua',
    'client/ai.lua',
    'client/interact.lua',
    'client/dispatch.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
