---@type table Generated glyph metrics (shared/glyphs.lua).
local Glyphs = require 'shared.glyphs'

---Animated colour effects, in the spirit of keyboard RGB.
---
---Colour is a per-entity tint index, so "animating" is just writing a new index to the
---same entity each tick. Every mode therefore costs exactly one entity per letter,
---whether it reaches two colours or all ten.
---
---This used to be far more expensive: with colour baked into the model, animating
---meant pre-spawning one entity per reachable palette index and flipping visibility,
---so a ten-colour wave cost ten entities per letter.
---
---Pure maths, no natives: the server validates modes with the same table.
local Anim = {}

local N = #Glyphs.COLOURS          -- palette size (10)
local WHITE = 0                    -- palette index of white, used as the "hot" colour

---@class AnimMode
---@field id string
---@field label string
---@field dynamic boolean whether it changes over time (and so needs the animation tick)

Anim.MODES = {
    { id = 'off',      label = 'None',     dynamic = false },
    { id = 'gradient', label = 'Gradient', dynamic = false },
    { id = 'cycle',    label = 'Cycle',    dynamic = true  },
    { id = 'wave',     label = 'Wave',     dynamic = true  },
    { id = 'chase',    label = 'Chase',    dynamic = true  },
    { id = 'pulse',    label = 'Pulse',    dynamic = true  },
}

---@type table<string, AnimMode>
local BY_ID = {}
for _, m in ipairs(Anim.MODES) do BY_ID[m.id] = m end

Anim.DEFAULT_SPEED = 2.0
Anim.MIN_SPEED = 0.25
Anim.MAX_SPEED = 10.0

---@param mode any
---@return string a valid mode id
function Anim.sanitise(mode)
    return BY_ID[mode] and mode or 'off'
end

---@param mode string
---@return boolean
function Anim.isDynamic(mode)
    local m = BY_ID[mode]
    return m ~= nil and m.dynamic
end

---Palette index for a letter at a given moment.
---
---Steps are deliberately integral rather than smoothly interpolated: the palette has
---ten discrete colours, so this reads like a row of LEDs rather than a smeared blend.
---@param mode string
---@param i integer 1-based letter index
---@param count integer total letters
---@param t number seconds
---@param speed number steps per second
---@param base integer the sign's own palette index, used where a mode keeps it
---@return integer palette index 0..N-1
function Anim.indexFor(mode, i, count, t, speed, base)
    if mode == 'gradient' then
        -- Spread the whole palette across the sign, fixed in place.
        if count <= 1 then return base end
        return math.floor((i - 1) / count * N) % N
    elseif mode == 'cycle' then
        return math.floor(t * speed) % N
    elseif mode == 'wave' then
        -- Same cycle, offset per letter: the rainbow appears to travel along.
        return (math.floor(t * speed) + (i - 1)) % N
    elseif mode == 'chase' then
        local lit = math.floor(t * speed) % math.max(1, count)
        return (i - 1) == lit and WHITE or base
    elseif mode == 'pulse' then
        -- Whole sign alternates between its colour and white, like a breath.
        return (math.floor(t * speed) % 2 == 0) and base or WHITE
    end
    return base
end

return Anim
