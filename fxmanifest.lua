fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'

description 'rsg-weaponcomp'
version '2.8.0'

shared_script {
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/*.lua'
}

client_scripts {
    'client/NUIMenu.lua',
    'client/client.lua',
    'client/dataview.lua',
    'client/inhands.lua',
    'client/inspect.lua',
    'client/propplace.lua',
    'client/test.lua',
}

files {
    'locales/*.json',
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

ui_page 'html/index.html'

dependencies {
    'oxmysql',
    'ox_lib',
    'rsg-core',
}

lua54 'yes'
