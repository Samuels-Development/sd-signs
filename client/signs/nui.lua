---@type table sd-signs config root (configs/config.lua).
local config = require 'configs.config'
---@type table Console log helper (shared/log.lua): tagged, colour-coded prints.
local log    = require 'shared.log'
---@type table Sign geometry + validation (shared/sign.lua).
local Sign   = require 'shared.sign'
---@type table Free placement mode (client/signs/placer.lua).
local Placer = require 'client.signs.placer'
---@type table Floating live preview (client/signs/preview.lua).
local Preview = require 'client.signs.preview'
---@type table Placed-sign registry (client/signs/world.lua).
local World  = require 'client.signs.world'

---Owns the sign panel (Build / Placed tabs) and the hand-off into placement mode.
local Nui = {}

---@type boolean
local open = false

---Payload shared by both tabs, so switching tabs never needs a round trip.
---@param tab string 'build' | 'placed'
---@param draft table|nil
---@param editingId number|nil
local function payload(tab, draft, editingId)
    -- Copied rather than sent by reference: the render-distance bounds live at the
    -- config root, not under Limits, and writing them into config.Limits would
    -- permanently graft two extra keys onto the config table at runtime.
    local limits = {}
    for k, v in pairs(config.Limits) do limits[k] = v end
    limits.maxRenderDistance = config.MaxRenderDistance
    limits.renderDistance    = config.RenderDistance   -- default for new signs

    return {
        tab     = tab,
        draft   = draft or config.Defaults,
        editing = editingId,
        colours = Sign.COLOURS,
        styles  = Sign.STYLES,
        anims   = Sign.ANIMS,
        limits  = limits,
        signs   = World.list(GetEntityCoords(cache.ped)),
        -- Placement mode is resolved fresh every open: object_gizmo can be started or
        -- stopped without restarting this resource, so the panel must not cache it.
        placement = {
            mode        = Placer.mode(),
            gizmo       = Placer.gizmoAvailable(),
            allowSwitch = config.Placement.allowSwitch,
        },
    }
end

---Close the panel and release focus. Idempotent.
function Nui.close()
    if not open then return end
    open = false
    Preview.hide()
    World.clearOverrides()   -- an unsaved edit must not linger in the world
    -- The highlight is a list affordance, so it goes with the list. Leaving a sign
    -- outlined out in the world after the panel is gone would look like a bug with no
    -- obvious way to turn it off.
    World.highlight(nil)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'signs:close' })
end

---Open the panel on a given tab.
---@param tab string|nil 'build' (default) or 'placed'
---@param draft table|nil pre-filled builder values
---@param editingId number|nil when set, the builder saves onto this sign
function Nui.open(tab, draft, editingId)
    if open or Placer.isActive() then return end
    open = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'signs:open', data = payload(tab or 'build', draft, editingId) })
end

---Live in-world preview: the panel pushes the current form here as it is edited.
---
---Two different things depending on context. Building something new floats a sign in
---front of the camera. EDITING an existing one instead re-renders that sign where it
---already stands -- floating a copy would leave the original unchanged beside it,
---which looks like the edit spawned a duplicate rather than changing anything.
RegisterNUICallback('signs:builder:preview', function(data, cb)
    cb({ ok = true })
    if not data or data.visible == false then
        Preview.hide()
        World.clearOverrides()
        return
    end

    -- Any editing id at all means "change that sign", never "float a copy". Falling
    -- through to the floating preview because the sign is momentarily missing would
    -- put a clone next to the original, which reads as having duplicated it.
    local id = tonumber(data.editing)
    if id then
        Preview.hide()
        local record = Sign.normalise(data)
        if record and World.get(id) then World.setOverride(id, record) end
        return
    end

    World.clearOverrides()
    Preview.show(data)
end)

RegisterNUICallback('signs:close', function(_, cb)
    Nui.close()
    cb({ ok = true })
end)

---Switch between raycast and gizmo placement. Client-side and session-only: the mode
---is how this player likes to drag signs around, not a property of any sign.
RegisterNUICallback('signs:builder:mode', function(data, cb)
    Placer.setMode(data and data.mode)
    cb({ ok = true, mode = Placer.mode() })
end)

---Live width readout, computed with the same layout maths the world uses so the
---number in the UI is the number you get.
RegisterNUICallback('signs:builder:measure', function(data, cb)
    local text = Sign.sanitiseText(data and data.text)
    if text == '' then
        cb({ width = 0.0, letters = 0, clean = '' })
        return
    end
    local size     = tonumber(data.size) or config.Defaults.size
    local tracking = tonumber(data.tracking) or config.Defaults.tracking
    local letters  = Sign.layout(text, size, tracking, config.Defaults.colour)
    cb({ width = Sign.width(text, size, tracking), letters = #letters, clean = text })
end)

---Build a normalised record out of a NUI form payload.
local function fromForm(data, base)
    return Sign.normalise({
        text = data.text, colour = data.colour, colours = data.colours, style = data.style,
        anim = data.anim, animSpeed = data.animSpeed, spin = data.spin,
        renderDistance = data.renderDistance,
        size = data.size, thickness = data.thickness, tracking = data.tracking,
        x = base and base.x or 0.0, y = base and base.y or 0.0,
        z = base and base.z or 0.0, heading = base and base.heading or 0.0,
    })
end

---New sign: drop the UI and go straight into placement.
RegisterNUICallback('signs:builder:place', function(data, cb)
    cb({ ok = true })
    local record = fromForm(data)
    if not record then
        lib.notify({ type = 'error', description = 'That sign has no printable characters.' })
        return
    end

    Nui.close()
    Preview.hide()   -- the placer's ghost takes over from here
    Wait(50)   -- let focus actually drop before the placer starts eating controls

    Placer.start(record, function(placed)
        if not placed then
            log.debug('place', 'placement cancelled, reopening the builder')
            Nui.open('build', record)
            return
        end
        TriggerServerEvent('sd-signs:server:create', placed)
    end)
end)

---Existing sign: save appearance changes without moving it.
RegisterNUICallback('signs:builder:save', function(data, cb)
    local id = tonumber(data and data.id)
    local existing = id and World.get(id)
    if not existing then cb({ ok = false }); return end
    local record = fromForm(data, existing)
    if not record then
        cb({ ok = false })
        lib.notify({ type = 'error', description = 'That sign has no printable characters.' })
        return
    end
    record.id = id
    World.clearOverrides()   -- the server broadcast is what renders from here
    TriggerServerEvent('sd-signs:server:update', id, record)
    cb({ ok = true })
    lib.notify({ description = ('Sign #%d updated.'):format(id) })
end)

---Existing sign: re-run placement to move it, keeping its id.
RegisterNUICallback('signs:builder:move', function(data, cb)
    cb({ ok = true })
    local id = tonumber(data and data.id)
    local existing = id and World.get(id)
    if not existing then return end
    local record = fromForm(data, existing)
    if not record then return end
    record.id = id

    Nui.close()
    Wait(50)
    Placer.start(record, function(placed)
        if not placed then
            Nui.open('build', record, id)
            return
        end
        TriggerServerEvent('sd-signs:server:update', id, placed)
    end)
end)

-- ------------------------------------------------------------- placed tab ----

RegisterNUICallback('signs:overview:refresh', function(_, cb)
    cb({ signs = World.list(GetEntityCoords(cache.ped)) })
end)

RegisterNUICallback('signs:overview:delete', function(data, cb)
    local id = tonumber(data and data.id)
    if not id then cb({ ok = false }); return end
    TriggerServerEvent('sd-signs:server:remove', id)
    cb({ ok = true })
end)

---Wipe every sign. The panel confirms before it gets here; the server re-checks ACE.
RegisterNUICallback('signs:overview:deleteAll', function(_, cb)
    World.highlight(nil)   -- nothing left to point at
    TriggerServerEvent('sd-signs:server:removeAll')
    cb({ ok = true })
end)

---Pick a sign out of the world without closing the panel, so you can walk down the
---list and confirm which row is which before editing or deleting one.
RegisterNUICallback('signs:overview:highlight', function(data, cb)
    local id = tonumber(data and data.id)
    if not id or not World.get(id) then cb({ ok = false, active = nil }); return end
    -- Toggling is decided in Lua, not the panel: Lua is what actually holds the
    -- outline, so it is the only place that can say what is lit without the two
    -- drifting apart. The panel just renders whatever comes back.
    cb({ ok = true, active = World.highlight(id) })
end)

RegisterNUICallback('signs:overview:teleport', function(data, cb)
    local id = tonumber(data and data.id)
    local rec = id and World.get(id)
    if not rec then cb({ ok = false }); return end
    cb({ ok = true })

    Nui.close()
    -- Stand back from the sign and face it, rather than landing inside the letters.
    local back = math.rad(rec.heading)
    local dist = math.max(4.0, rec.size * 6.0)
    local x = rec.x + math.sin(back) * dist
    local y = rec.y - math.cos(back) * dist

    DoScreenFadeOut(300)
    while not IsScreenFadedOut() do Wait(0) end
    SetEntityCoords(cache.ped, x, y, rec.z + 1.0, false, false, false, false)
    SetEntityHeading(cache.ped, (rec.heading + 180.0) % 360.0)
    Wait(400)
    DoScreenFadeIn(400)
    lib.notify({ description = ('Teleported to sign #%d'):format(id) })
end)

return Nui
