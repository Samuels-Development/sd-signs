---@type table sd-signs config root (configs/config.lua).
local config  = require 'configs.config'
---@type table Console log helper (shared/log.lua): tagged, colour-coded prints.
local log     = require 'shared.log'
---@type table Sign geometry + validation (shared/sign.lua).
local Sign    = require 'shared.sign'
---@type table Colour effect maths (shared/anim.lua).
local Anim    = require 'shared.anim'
---@type table Turns a sign record into entities (client/signs/builder.lua).
local Builder = require 'client.signs.builder'

---Owns every placed sign on this client and decides which ones are currently spawned,
---and which of those are cheap enough to animate.
local World = {}

---@type table<number, table> signId -> record
local signs = {}
---@type table<number, table> signId -> built payload (present only while spawned)
local built = {}
---@type table<number, boolean> signId -> whether its colours are currently being animated
local animating = {}
---@type table<number, table> signId -> unsaved local edit, rendered instead of the record
---
---While a sign is being edited the builder pushes the in-progress draft here, so the
---real sign updates where it stands. Rendering a separate floating copy would leave
---the original sitting unchanged beside it, which reads as having made a duplicate.
local overrides = {}

---The record that should actually be rendered for a sign.
---@param id number
---@return table|nil
local function effective(id)
    return overrides[id] or signs[id]
end

---Entities a sign costs: one per letter, animated or not.
---
---Sign.layout already drops spaces and characters with no glyph, so its length is the
---entity count exactly rather than an upper bound on it.
local function letterCountOf(rec)
    return #Sign.layout(rec.text, rec.size, rec.tracking, rec.colour, rec.colours, rec.style)
end

local function spawn(id)
    if built[id] then return end
    local rec = effective(id)
    if not rec then return end
    built[id] = Builder.build(rec, false)
    log.debug('build', 'spawned sign %d (%q) as %d entities',
        id, rec.text, #built[id].entities)
end

local function despawn(id)
    if not built[id] then return end
    Builder.destroy(built[id])
    built[id] = nil
    animating[id] = nil
end

---Replace the whole registry (used on join and on full resyncs).
---@param list table array of sign records, each carrying an `id`
function World.sync(list)
    for id in pairs(built) do despawn(id) end
    signs = {}
    for _, rec in ipairs(list or {}) do
        if rec.id then signs[rec.id] = rec end
    end
    log.debug('net', 'synced %d sign(s)', #(list or {}))
end

---@param record table must carry `id`
function World.add(record)
    if not record or not record.id then return end
    -- A server update supersedes any local edit-in-progress for that sign.
    overrides[record.id] = nil
    despawn(record.id)
    signs[record.id] = record
end

---Render `rec` in place of sign `id` without saving anything. Pass nil to revert.
---
---The transform always comes from the stored sign: editing changes how a sign looks,
---not where it is. Moving is a separate action that re-runs the placer.
---@param id number
---@param rec table|nil
function World.setOverride(id, rec)
    local base = signs[id]
    if not base then return end
    if rec then
        rec.x, rec.y, rec.z, rec.heading = base.x, base.y, base.z, base.heading
        rec.id = id
        overrides[id] = rec
    else
        overrides[id] = nil
    end
    -- Rebuild immediately rather than waiting up to a second for the housekeeping
    -- tick; this is driven by someone dragging a slider and has to feel live.
    local wasAnimated = animating[id]
    despawn(id)
    spawn(id)
    -- despawn() cleared the flag. Restoring it keeps the effect running through the
    -- edit instead of stalling until the next housekeeping pass re-grants it.
    animating[id] = wasAnimated
end

---Drop every unsaved edit and restore the stored records.
function World.clearOverrides()
    for id in pairs(overrides) do
        overrides[id] = nil
        local wasAnimated = animating[id]
        despawn(id)
        spawn(id)
        animating[id] = wasAnimated
    end
end

---@param id number
function World.remove(id)
    despawn(id)
    signs[id] = nil
end

---@param id number
---@return table|nil record
function World.get(id) return signs[id] end

---The nearest sign to a point within `maxDist`.
function World.nearest(x, y, z, maxDist)
    local bestId, bestD
    for id, rec in pairs(signs) do
        local d = #(vec3(x, y, z) - vec3(rec.x, rec.y, rec.z))
        if d <= maxDist and (not bestD or d < bestD) then bestId, bestD = id, d end
    end
    return bestId, bestD
end

---Every known sign, newest first, annotated for the overview list.
---@param from vector3
---@return table[]
function World.list(from)
    local out = {}
    for id, rec in pairs(signs) do
        local d = #(from - vec3(rec.x, rec.y, rec.z))
        out[#out + 1] = {
            id = id, text = rec.text, colour = rec.colour, colours = rec.colours,
            style = rec.style, anim = rec.anim, animSpeed = rec.animSpeed, spin = rec.spin,
            renderDistance = rec.renderDistance,
            size = rec.size, thickness = rec.thickness, tracking = rec.tracking,
            x = rec.x, y = rec.y, z = rec.z, heading = rec.heading,
            owner = rec.owner, distance = d, spawned = built[id] ~= nil,
        }
    end
    -- Newest first. Ids are auto-increment, so descending id is "most recently placed
    -- at the top", which is almost always the one you came here to find. Distance is
    -- still shown on every row, and the Go button is how you act on it.
    table.sort(out, function(a, b) return a.id > b.id end)
    return out
end

---@return number count of signs known to this client
function World.count()
    local n = 0
    for _ in pairs(signs) do n = n + 1 end
    return n
end

---@type number|nil sign currently being highlighted from the overview list
local litId

---Turn the outline on or off across every letter of a sign.
---@param id number|nil
---@param on boolean
local function outline(id, on)
    local b = id and built[id]
    if not b then return end
    for _, ent in pairs(b.letters or {}) do
        if DoesEntityExist(ent) then SetEntityDrawOutline(ent, on) end
    end
end

---Toggle a sign's highlight so you can tell which row of the list it is.
---
---Uses the same SetEntityDrawOutline the gizmo uses on the entity it manipulates, on
---every letter rather than one. A sign past its render distance has no letters to
---outline at all, which is exactly when "which one is this?" is hardest to answer, so
---it also gets a marker overhead -- that part works whether or not it is spawned.
---
---A toggle rather than a timed flash: comparing two signs means looking away from the
---panel, and a highlight that expired on its own timer would keep going out while you
---were still deciding. Clicking the same sign again, or a different one, clears it.
---@param id number|nil nil clears any current highlight
---@return number|nil id the sign now highlighted, nil when nothing is
function World.highlight(id)
    local was = litId
    if was then outline(was, false) end
    litId = (id and id ~= was and signs[id]) and id or nil
    return litId
end

CreateThread(function()
    while true do
        if not litId then
            Wait(250)
        else
            local rec = effective(litId)
            if not rec then
                litId = nil
            else
                -- Re-asserted every frame rather than once: the housekeeping tick can
                -- despawn and respawn a sign underneath us (crossing the animation
                -- threshold, or an edit landing), and the new entities would come back
                -- without the outline.
                outline(litId, true)

                -- Sits above the tallest glyph and scales with the sign, so it is
                -- still findable on a 100 m one and not absurd on a 1 m one.
                local above = select(1, Sign.verticalExtent(rec.text, rec.size))
                local bob = math.sin(GetGameTimer() / 220.0) * rec.size * 0.15
                local m = math.max(0.6, rec.size * 0.8)
                -- Trailing texture args are omitted rather than passed as nil: the
                -- marker is untextured, and Lua fills the gap with nil anyway.
                DrawMarker(2, rec.x, rec.y, rec.z + above + rec.size * 0.9 + bob,
                    0.0, 0.0, 0.0, 180.0, 0.0, 0.0, m, m, m,
                    255, 255, 255, 190, false, false, 2, true)
                Wait(0)
            end
        end
    end
end)

-- Spawn/despawn by distance, and decide which signs are close enough to animate.
CreateThread(function()
    while true do
        local pc = GetEntityCoords(cache.ped)
        local anim = config.Animation

        -- Nearest first, so a limited animation budget goes to the signs the player
        -- is actually looking at rather than whichever hashed first.
        local ordered = {}
        for id, rec in pairs(signs) do
            ordered[#ordered + 1] = { id = id, d = #(pc - vec3(rec.x, rec.y, rec.z)) }
        end
        table.sort(ordered, function(a, b) return a.d < b.d end)

        local cap = config.EntityBudget
        local spent, total = 0, 0
        for _, entry in ipairs(ordered) do
            local id, rec, d = entry.id, effective(entry.id), entry.d
            -- Per-sign range, falling back to the config default. Signs placed before
            -- the slider existed store nil, so one config edit still moves them all.
            if not rec or d > (rec.renderDistance or config.RenderDistance) then
                despawn(id)
            else
                local letters = letterCountOf(rec)
                if cap and total + letters > cap then
                    -- Out of entity budget. The list is nearest-first, so everything
                    -- shed from here on is farther than everything already kept.
                    despawn(id)
                else
                    total = total + letters
                    spawn(id)

                    -- An animated sign is the same entities as a static one, so this
                    -- budget is about how much tint-writing runs per tick, not about
                    -- objects, and crossing the threshold never needs a rebuild.
                    local wantAnim = Anim.isDynamic(Anim.sanitise(rec.anim))
                        and d <= anim.distance
                        and spent + letters <= anim.letterBudget
                    if wantAnim then
                        spent = spent + letters
                    elseif animating[id] and built[id] then
                        -- Stopped animating: put the letters back to their resting
                        -- colours, or they keep whichever tint the last tick wrote.
                        Builder.tint(built[id], rec, 0)
                    end
                    animating[id] = wantAnim or nil
                end
            end
        end
        Wait(1000)
    end
end)

---Rotation about the vertical axis.
---
---Spinning is just the sign's heading advancing over time, since the letter layout is
---already derived from it. The stored heading is never mutated -- it stays the resting
---angle, and the turn is passed to reposition as an override. Otherwise a sign would
---creep away from where it was placed and "save" would bake in whatever angle it
---happened to be at.
CreateThread(function()
    local interval = math.floor(1000 / math.max(1, config.Animation.spinRate))
    while true do
        local spinning, pc = false, GetEntityCoords(cache.ped)
        local t = GetGameTimer() / 1000.0
        for id, b in pairs(built) do
            local rec = effective(id)
            local speed = rec and rec.spin or 0
            if rec and speed > 0 then
                -- Only turn what is close enough to read as turning.
                if #(pc - vec3(rec.x, rec.y, rec.z)) <= config.Animation.distance then
                    spinning = true
                    Builder.reposition(b, rec, (rec.heading + speed * t) % 360.0)
                end
            end
        end
        Wait(spinning and interval or 500)
    end
end)

-- Drive the colour animation. Visibility flips only, no entity churn.
CreateThread(function()
    local interval = math.floor(1000 / math.max(1, config.Animation.rate))
    while true do
        if next(animating) ~= nil then
            local t = GetGameTimer() / 1000.0
            for id in pairs(animating) do
                local rec = effective(id)
                if built[id] and rec then Builder.tint(built[id], rec, t) end
            end
            Wait(interval)
        else
            Wait(500)   -- nothing animated: idle cheaply
        end
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= cache.resource then return end
    for id in pairs(built) do despawn(id) end
end)

return World
