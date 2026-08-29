---@type table sd-signs config root (configs/config.lua).
local config = require 'configs.config'
---@type table Console log helper (shared/log.lua): tagged, colour-coded prints.
local log    = require 'shared.log'
---@type table Placed-sign registry (client/signs/world.lua).
local World  = require 'client.signs.world'
---@type table Sign panel + placement hand-off (client/signs/nui.lua).
local Nui    = require 'client.signs.nui'
---@type table Free placement mode (client/signs/placer.lua).
local Placer = require 'client.signs.placer'

---Ask the server whether this player may use the sign tools.
---
---Gating here is a courtesy so the menu can refuse with a reason; the server
---re-checks on every create/remove, which is where it actually matters.
---@return boolean
local function authorised()
    if not config.Ace then return true end
    local ok = lib.callback.await('sd-signs:isAllowed', false)
    if not ok then
        lib.notify({
            type = 'error',
            description = 'You do not have permission to manage signs.',
        })
    end
    return ok and true or false
end

RegisterCommand(config.Command, function()
    if Placer.isActive() then
        lib.notify({ type = 'error', description = 'Finish placing the current sign first.' })
        return
    end
    if not authorised() then return end
    Nui.open('build')
end, false)

RegisterCommand(config.OverviewCommand, function()
    if Placer.isActive() then
        lib.notify({ type = 'error', description = 'Finish placing the current sign first.' })
        return
    end
    if not authorised() then return end
    Nui.open('placed')
end, false)

RegisterCommand(config.Command .. 'remove', function()
    if not authorised() then return end
    local pc = GetEntityCoords(cache.ped)
    local id, dist = World.nearest(pc.x, pc.y, pc.z, 12.0)
    if not id then
        lib.notify({ type = 'error', description = 'No sign within 12 m.' })
        return
    end
    TriggerServerEvent('sd-signs:server:remove', id)
    log.debug('net', 'requested removal of sign %d (%.1f m away)', id, dist or -1)
end, false)

RegisterNetEvent('sd-signs:client:sync', function(list)
    World.sync(list)
end)

RegisterNetEvent('sd-signs:client:add', function(record)
    World.add(record)
    log.debug('net', 'sign %s added', tostring(record and record.id))
end)

RegisterNetEvent('sd-signs:client:remove', function(id)
    World.remove(id)
end)

AddEventHandler('onClientResourceStart', function(name)
    if name ~= cache.resource then return end
    TriggerServerEvent('sd-signs:server:requestSync')
end)

CreateThread(function()
    Wait(2000)
    if World.count() == 0 then TriggerServerEvent('sd-signs:server:requestSync') end
end)
