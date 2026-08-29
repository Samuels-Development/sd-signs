fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sd-signs'
author 'Samuel#0008'
version '1.1.0'
description '3D emissive channel-letter signs: type it, place it, scale it'

shared_scripts {
    '@ox_lib/init.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

ui_page 'web/build/index.html'

files {
    'configs/config.lua',
    'configs/*.lua',
    'shared/*.lua',
    'client/*.lua',
    'client/signs/*.lua',
    'stream/sd_a3d.ytyp',
    'web/build/index.html',
    'web/build/assets/*.js',
    'web/build/assets/*.css',
}

data_file 'DLC_ITYP_REQUEST' 'stream/sd_a3d.ytyp'

dependencies {
    'ox_lib',
    'oxmysql',
}
