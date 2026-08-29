---@type table sd-signs config root (configs/config.lua).
local config  = require 'configs.config'
---@type table Console log helper (shared/log.lua): tagged, colour-coded prints.
local log     = require 'shared.log'
---@type table Sign geometry + validation (shared/sign.lua).
local Sign    = require 'shared.sign'
---@type table Turns a sign record into entities (client/signs/builder.lua).
local Builder = require 'client.signs.builder'
---@type table Colour effect maths (shared/anim.lua).
local Anim    = require 'shared.anim'

---Free placement: a translucent ghost of the sign tracks whatever the camera is
---pointed at, and the player nudges it into place before committing.
local Placer = {}

---@type boolean
local active = false
---@type table|nil entities of the ghost currently being dragged
local ghost
---@type table|nil the record being placed
local draft
---@type fun(record: table|nil)|nil called with the record on confirm, nil on cancel
local onFinish
---@type number|nil invisible entity the gizmo manipulates, in gizmo mode only
local anchor
---@type string the mode this client is currently placing with
local mode = config.Placement.default

---True when the optional object_gizmo resource is actually running.
---
---Checked live rather than cached: object_gizmo can be started or stopped without
---restarting this resource, and a stale `true` would call a export that is not there.
---@return boolean
function Placer.gizmoAvailable()
    return GetResourceState('object_gizmo') == 'started'
end

---The mode placement would actually use right now, after availability and config.
---@return string 'raycast' | 'gizmo'
function Placer.mode()
    if mode == 'gizmo' and Placer.gizmoAvailable() then return 'gizmo' end
    return 'raycast'
end

---@param next string 'raycast' | 'gizmo'
function Placer.setMode(next)
    if not config.Placement.allowSwitch then return end
    if next == 'gizmo' or next == 'raycast' then mode = next end
end

-- Control ids (group 0). Attack/aim are consumed so placing never fires a weapon.
local CONTROL = {
    confirm    = 24,   -- LMB
    cancel     = 25,   -- RMB
    back       = 177,  -- Backspace
    scrollUp   = 15,
    scrollDown = 14,
    raise      = 172,  -- arrow up
    lower      = 173,  -- arrow down
    fine       = 21,   -- Shift: coarser/faster adjustment
}

local BLOCKED = { 24, 25, 140, 141, 142, 257, 263, 264, 331 }

---Direction the gameplay camera is looking, as a unit vector.
---@param rot vector3 camera rotation (rotation order 2)
---@return vector3
local function rotToDir(rot)
    local rz, rx = math.rad(rot.z), math.rad(rot.x)
    local flat = math.abs(math.cos(rx))
    return vec3(-math.sin(rz) * flat, math.cos(rz) * flat, math.sin(rx))
end

---Cast from the camera and return where the sign should sit.
---Ghost letters have collision disabled, so the probe passes straight through them
---and cannot chase its own preview.
---Always returns a position: when nothing is struck the sign hangs at arm's length,
---which is what you want for placing a sign on a wall face or out over a drop.
---@return vector3 hit, vector3|nil surfaceNormal
local function probe()
    local from = GetGameplayCamCoord()
    local dir  = rotToDir(GetGameplayCamRot(2))
    local to   = from + dir * config.PlaceReach
    local ray  = StartShapeTestRay(from.x, from.y, from.z, to.x, to.y, to.z, -1, cache.ped, 4)
    local _, hit, endCoords, normal = GetShapeTestResult(ray)
    if hit == 1 then return endCoords, normal end
    return to, nil
end

---Stop placement, tear down the ghost and hand the result to the caller.
---@param record table|nil nil when cancelled
local function finish(record)
    if not active then return end
    active = false
    Builder.destroy(ghost)
    if anchor and DoesEntityExist(anchor) then DeleteEntity(anchor) end
    ghost, draft, anchor = nil, nil, nil
    lib.hideTextUI()
    local cb = onFinish
    onFinish = nil
    if cb then cb(record) end
end

Placer.cancel = function() finish(nil) end

---True while the player is dragging a sign around.
function Placer.isActive() return active end

---The draft as a plain record for the caller.
---
---Copies the WHOLE draft rather than listing fields by hand. An explicit field list
---silently drops anything added later (style and the per-letter colours were both lost
---this way: the ghost renders from the draft, so it looked correct right up until you
---clicked).
---@return table
local function harvest()
    local out = {}
    for k, v in pairs(draft or {}) do out[k] = v end
    out.zOffset = nil          -- placer-internal, not part of a sign
    return out
end

---Drag the sign with object_gizmo's handles.
---
---The gizmo drives ONE entity, and a sign is one entity per letter, so it is given an
---invisible anchor and the letters follow it. The anchor reuses a model this sign
---already streams, so nothing extra has to be requested.
local function runGizmo()
    anchor = CreateObject(GetEntityModel(ghost.entities[1]),
        draft.x, draft.y, draft.z, false, false, false)
    SetEntityVisible(anchor, false, false)
    SetEntityCollision(anchor, false, false)
    SetEntityHeading(anchor, draft.heading)

    -- Highlight the LETTERS, not the anchor.
    --
    -- object_gizmo outlines whatever entity it is handed, and that is the anchor: one
    -- invisible glyph sitting at the sign's origin. Left alone it draws a single
    -- letter-shaped silhouette in the middle of the sign, which reads as a broken
    -- highlight of the wrong thing.
    --
    -- The letters also go solid here. The ghost's translucency earns its place in the
    -- raycast drag, where the sign sweeps through walls and you need to see past it;
    -- with the gizmo the sign holds still and being able to read it matters more.
    for _, ent in ipairs(ghost.entities) do
        if DoesEntityExist(ent) then
            ResetEntityAlpha(ent)
            SetEntityDrawOutline(ent, true)
        end
    end

    lib.showTextUI(
        ('**Placing sign** — gizmo  \n' ..
         '[W] move  •  [R] turn  •  [Q] local/world  •  [Alt] drop to ground  \n' ..
         '[Enter] place  •  [Backspace] cancel'),
        { position = 'left-center' })

    -- The gizmo owns the anchor; this makes the letters follow it.
    CreateThread(function()
        while active and anchor and DoesEntityExist(anchor) do
            -- Cleared every frame rather than once: useGizmo sets it from its own
            -- thread after this loop has already started, so a single call up front
            -- races it and loses about half the time.
            SetEntityDrawOutline(anchor, false)

            local c = GetEntityCoords(anchor)
            local r = GetEntityRotation(anchor, 2)
            -- A sign stores a single heading. Hold pitch and roll at zero so tilting
            -- is visibly refused while dragging, rather than appearing to work and
            -- then snapping flat the moment it is committed.
            if math.abs(r.x) > 0.01 or math.abs(r.y) > 0.01 then
                SetEntityRotation(anchor, 0.0, 0.0, r.z, 2, true)
            end
            draft.x, draft.y, draft.z = c.x, c.y, c.z
            draft.heading = r.z % 360.0

            local spin = draft.spin or 0
            Builder.reposition(ghost, draft,
                spin > 0 and (draft.heading + spin * (GetGameTimer() / 1000.0)) % 360.0 or nil)
            if Anim.isDynamic(Anim.sanitise(draft.anim)) then
                Builder.tint(ghost, draft, GetGameTimer() / 1000.0)
            end

            -- object_gizmo's only exit is Enter/confirm, so cancel is ours to provide.
            if IsControlJustPressed(0, CONTROL.back) then
                finish(nil)
                return
            end
            Wait(0)
        end
    end)

    CreateThread(function()
        -- Blocks until the player confirms. Deleting the anchor also ends it, which is
        -- what makes the Backspace cancel above work.
        local result = exports.object_gizmo:useGizmo(anchor)
        if not active then return end          -- cancelled: finish() already ran
        if result and result.position then
            draft.x, draft.y, draft.z = result.position.x, result.position.y, result.position.z
            if result.rotation then draft.heading = result.rotation.z % 360.0 end
        end
        finish(harvest())
    end)
end

---Drag the sign on a camera raycast: the original, and the fallback when
---object_gizmo is not installed.
local function runRaycast()
    lib.showTextUI(
        ('**Placing sign**  \n' ..
         '[LMB] place  •  [RMB] cancel  \n' ..
         'Scroll rotate  •  ↑ / ↓ height  •  Shift = faster'),
        { position = 'left-center' })

    CreateThread(function()
        while active do
            local hit = probe()
            local fast = IsControlPressed(0, CONTROL.fine)

            if IsControlJustPressed(0, CONTROL.raise) or IsControlPressed(0, CONTROL.raise) then
                draft.zOffset = draft.zOffset + (fast and 0.08 or 0.02)
            elseif IsControlJustPressed(0, CONTROL.lower) or IsControlPressed(0, CONTROL.lower) then
                draft.zOffset = draft.zOffset - (fast and 0.08 or 0.02)
            end

            if IsControlJustPressed(0, CONTROL.scrollUp) then
                draft.heading = (draft.heading + (fast and 15.0 or 3.0)) % 360.0
            elseif IsControlJustPressed(0, CONTROL.scrollDown) then
                draft.heading = (draft.heading - (fast and 15.0 or 3.0)) % 360.0
            end

            draft.x, draft.y = hit.x, hit.y
            draft.z = hit.z + draft.zOffset
            local spin = draft.spin or 0
            Builder.reposition(ghost, draft,
                spin > 0 and (draft.heading + spin * (GetGameTimer() / 1000.0)) % 360.0 or nil)
            if Anim.isDynamic(Anim.sanitise(draft.anim)) then
                Builder.tint(ghost, draft, GetGameTimer() / 1000.0)
            end

            for _, c in ipairs(BLOCKED) do DisableControlAction(0, c, true) end

            if IsDisabledControlJustPressed(0, CONTROL.confirm) then
                finish(harvest())
                return
            elseif IsDisabledControlJustPressed(0, CONTROL.cancel)
                or IsControlJustPressed(0, CONTROL.back) then
                finish(nil)
                return
            end
            Wait(0)
        end
    end)
end

---Begin placing `record`. `cb` receives the finished record, or nil if cancelled.
---@param record table normalised sign record (x/y/z/heading are overwritten while dragging)
---@param cb fun(record: table|nil)
function Placer.start(record, cb)
    if active then finish(nil) end
    active   = true
    onFinish = cb
    draft    = record
    draft.zOffset = 0.0

    -- Build the ghost animated too, so what you drag around is what you get.
    local first, missing = Builder.build(draft, true)
    ghost = first
    if missing > 0 and #ghost.entities == 0 then
        log.err('no letter models streamed -- cannot place. Check sd-signs/stream.')
        finish(nil)
        return
    end

    -- Start in front of the camera, aimed at the player; both modes take it from here.
    -- Set before the drag loop starts so the first frame is not drawn at the record's
    -- stale transform.
    local pc  = GetEntityCoords(cache.ped)
    local hit = probe()
    draft.x, draft.y, draft.z = hit.x, hit.y, hit.z
    draft.heading = Sign.headingToFace(hit.x, hit.y, pc.x, pc.y)
    Builder.reposition(ghost, draft)

    if Placer.mode() == 'gizmo' then runGizmo() else runRaycast() end
end

return Placer
