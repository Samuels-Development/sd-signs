fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sd-signs'
author 'Samuel#0008'
version '1.0.0'
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

-- ox_lib's require() reads these off the resource, so every module reachable from a
-- require call must be listed here, alongside the NUI bundle and the archetype file.
--
-- 'dir/**.lua' does NOT match files sitting directly in `dir`, only nested ones, so
-- the top-level modules are listed with a single star. With only ** globs every
-- require fails and neither script loads - silently, with nothing in the console.
--
-- stream/ is auto-detected for .ydr/.ytd and is deliberately absent: listing those
-- would ship every one of the 258 props twice. The .ytyp is the exception - it is
-- the archetype registry, and without the data_file below the models stream fine but
-- CreateObject cannot resolve their names.
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
