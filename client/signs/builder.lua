---@type table sd-signs config root (configs/config.lua).
local config = require 'configs.config'
---@type table Console log helper (shared/log.lua): tagged, colour-coded prints.
local log    = require 'shared.log'
---@type table Sign geometry + validation (shared/sign.lua).
local Sign   = require 'shared.sign'
---@type table Colour effect maths (shared/anim.lua).
local Anim   = require 'shared.anim'

---Turns a sign record into game entities.
---
---Every letter is a separate local (non-networked) object. Signs are never networked:
---SetEntityMatrix is a client-side visual and does not replicate, so each client builds
---its own copy from the synced record. That also keeps signs off the network entity
---budget entirely.
local Builder = {}

---Position + orient + scale one letter in a single pass.
---
---SetEntityHeading resets the entity's basis vectors to unit length, so the scale has
---to be re-applied after any rotation change -- hence heading and scale together here.
---
---Axis mapping for SetEntityMatrix, established by testing in game (the docs are
---commonly misquoted): arg1 -> model Y, arg2 -> model X, arg3 -> model Z.
---Our glyphs are modelled X = width, Y = thickness, Z = height.
local function orientAndScale(entity, x, y, z, heading, size, thickness)
    SetEntityCoordsNoOffset(entity, x, y, z, false, false, false)
    SetEntityHeading(entity, heading)
    local f, r, u = GetEntityMatrix(entity)
    local sy = size * thickness
    SetEntityMatrix(entity,
        f.x * sy, f.y * sy, f.z * sy,       -- model Y : thickness
        r.x * size, r.y * size, r.z * size, -- model X : width
        u.x * size, u.y * size, u.z * size, -- model Z : height
        x, y, z)
end

---Resolve a model name to a streamed hash, degrading gracefully.
---
---Prop sets ship incrementally, so try the painted version of the same colour first
---(a neon set that is not streamed yet still gives the right hue), then white. The
---shape is always right even when the finish or hue is not available.
---@param model string
---@return number|nil hash
local function resolveModel(model)
    local hash = joaat(model)
    if IsModelInCdimage(hash) then return hash end
    for _, candidate in ipairs({
        (model:gsub('_neon_', '_')),
        (model:gsub('_[^_]+$', '_white'):gsub('_neon_', '_')),
    }) do
        local h = joaat(candidate)
        if IsModelInCdimage(h) then return h end
    end
    return nil
end

---Spawn one letter entity.
local function spawnLetter(hash, x, y, z, record, ghost, visible)
    local model = lib.requestModel(hash, 5000)
    if not model then return nil end
    local ent = CreateObject(hash, x, y, z, false, false, false)
    SetEntityCollision(ent, config.Collision and not ghost, false)
    FreezeEntityPosition(ent, true)
    SetEntityInvincible(ent, true)
    if ghost then
        SetEntityAlpha(ent, 160, false)
        SetEntityNoCollisionEntity(ent, cache.ped, true)
    end
    if visible == false then SetEntityVisible(ent, false, false) end
    orientAndScale(ent, x, y, z, record.heading, record.size, record.thickness)
    SetModelAsNoLongerNeeded(hash)
    return ent
end

---Build the entities for a sign record: one entity per letter, always.
---
---Every mode costs the same now. Colour is a tint index written to the entity, so a
---ten-colour wave and a static sign are both one object per letter -- there is no
---variant stack and nothing to pre-spawn.
---@param record table normalised sign record
---@param ghost boolean|nil when true the letters are translucent and non-solid
---@return table built { entities = {...}, letters = {...}, base = {...}, count = n }
---@return number missing count of characters whose model is not streamed
function Builder.build(record, ghost)
    local letters = Sign.layout(record.text, record.size, record.tracking,
        record.colour, record.colours, record.style)
    local rx, ry = Sign.rightVector(record.heading)
    local mode = Anim.sanitise(record.anim)

    -- `letters` and `base` are keyed by LETTER index and so may have holes where a
    -- model failed to stream; `entities` is the dense list destroy() walks.
    local built = { entities = {}, letters = {}, base = {}, count = #letters, mode = mode }
    local missing = 0

    for i, letter in ipairs(letters) do
        local hash = letter.model and resolveModel(letter.model)
        if not hash then
            missing = missing + 1
        else
            -- `rise` stacks multi-row signs. It is 0 on a single-row sign, so this is
            -- a no-op for everything placed before rows existed.
            local ent = spawnLetter(hash, record.x + rx * letter.offset,
                record.y + ry * letter.offset, record.z + (letter.rise or 0.0),
                record, ghost, true)
            if not ent then
                missing = missing + 1
            else
                built.entities[#built.entities + 1] = ent
                built.letters[i] = ent
                built.base[i] = letter.tint
            end
        end
    end

    -- Static modes still resolve through Anim, so 'gradient' spreads the palette
    -- across the sign at no extra cost.
    Builder.tint(built, record, 0)

    if missing > 0 then
        log.warn('sign %q: %d letter model(s) not streamed -- is sd-signs/stream complete?',
            record.text, missing)
    end
    return built, missing
end

---Write the palette index every letter should show at time `t`.
---
---This is the whole of animation now. Passing t = 0 gives the sign's resting colours,
---which is how a sign that has just stopped animating is put back.
---@param built table
---@param record table
---@param t number seconds
function Builder.tint(built, record, t)
    if not built or not built.letters then return end
    local speed = record.animSpeed or Anim.DEFAULT_SPEED
    built.shown = built.shown or {}

    for i, ent in pairs(built.letters) do
        -- base is per LETTER, so a sign using per-letter colours keeps them under
        -- modes like chase and pulse that return to the letter's own colour.
        local want = Anim.indexFor(built.mode, i, built.count, t, speed, built.base[i] or 0)
        if built.shown[i] ~= want and DoesEntityExist(ent) then
            SetObjectTextureVariation(ent, want)
            built.shown[i] = want
        end
    end
end

---Move/rotate/rescale an already-built sign without respawning it. Used by the placer,
---which drags a live ghost around every frame.
---@param built table
---@param record table
---@param heading number|nil overrides record.heading (used by the spin tick, so the
---stored heading stays the sign's resting angle rather than drifting)
function Builder.reposition(built, record, heading)
    local letters = Sign.layout(record.text, record.size, record.tracking,
        record.colour, record.colours, record.style)
    local h = heading or record.heading
    local rx, ry = Sign.rightVector(h)

    -- Keyed by letter index rather than walking `entities`, so a sign with an
    -- unstreamed glyph does not shift every letter after it onto the wrong offset.
    for i, ent in pairs(built.letters or {}) do
        local letter = letters[i]
        if letter and DoesEntityExist(ent) then
            orientAndScale(ent,
                record.x + rx * letter.offset,
                record.y + ry * letter.offset,
                record.z + (letter.rise or 0.0), h, record.size, record.thickness)
        end
    end
end

---Delete every entity of a built sign.
---@param built table|nil
function Builder.destroy(built)
    if not built then return end
    for _, ent in ipairs(built.entities or {}) do
        if DoesEntityExist(ent) then DeleteEntity(ent) end
    end
end

---True when the record's shape (not its transform) changed enough to need a rebuild.
---Text, colour and finish pick different models; size/tracking only move existing ones.
---@param a table|nil
---@param b table
---@return boolean
function Builder.needsRebuild(a, b)
    if not a then return true end
    return a.text ~= b.text or a.colour ~= b.colour or a.colours ~= b.colours
        or a.style ~= b.style or a.anim ~= b.anim
end

return Builder
