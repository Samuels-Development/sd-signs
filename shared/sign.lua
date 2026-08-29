---@type table Generated glyph metrics (shared/glyphs.lua).
local Glyphs = require 'shared.glyphs'
---@type table Colour effect maths (shared/anim.lua).
local Anim   = require 'shared.anim'
---@type table sd-signs config root (configs/config.lua).
local config = require 'configs.config'

---Pure geometry + validation for signs. No natives in here, so the server can clamp
---and measure a submitted sign with exactly the same maths the client laid it out with.
---
---Everything works on whole UTF-8 characters. The glyph set includes multi-byte
---symbols (arrows, currency, fractions), and byte-wise iteration would never match
---their keys -- it would quietly delete every non-ASCII symbol a player typed.
local Sign = {}

Sign.COLOURS = Glyphs.COLOURS
Sign.STYLES  = Glyphs.STYLES
Sign.ANIMS   = Anim.MODES

--- Baseline-to-baseline distance between rows, in cap-height units.
---
--- Cap height is 1.0 and descenders reach roughly -0.22, so 1.35 clears a `g` on the
--- row above from a capital below with a little air left. Expressed in cap heights,
--- like tracking, so it scales with the sign rather than needing its own slider.
Sign.LINE = 1.35

---@type table<string, boolean>
local STYLE_SET = {}
for _, s in ipairs(Glyphs.STYLES) do STYLE_SET[s] = true end

---@type table<string, boolean>
local COLOUR_SET = {}
for _, c in ipairs(Glyphs.COLOURS) do COLOUR_SET[c] = true end

-- Colour name -> index lives in Glyphs.TINT, because that index is now the model's
-- tint row rather than a private numbering. Use Glyphs.tint(name).

---Per-character colours travel as a string of palette digits, one per character of
---`text` (spaces included, so indices line up). "0132" means white, red, amber, orange.
---Compact enough for a VARCHAR, trivial to validate, and always ASCII so it can be
---indexed byte-wise even when the text itself is multi-byte.
---@param colours any
---@param charCount integer
---@return string|nil valid digit string, or nil when absent/malformed
local function normaliseColours(colours, charCount)
    if type(colours) ~= 'string' or #colours ~= charCount then return nil end
    local palette = #Glyphs.COLOURS
    for i = 1, #colours do
        local d = tonumber(colours:sub(i, i))
        if not d or d < 0 or d >= palette then return nil end
    end
    return colours
end

---Colour name for character `index`, falling back to the sign's base colour.
---@param base string
---@param colours string|nil
---@param index integer 1-based character index
---@return string
function Sign.colourAt(base, colours, index)
    if not colours then return base end
    local d = tonumber(colours:sub(index, index))
    if not d then return base end
    return Glyphs.COLOURS[d + 1] or base
end

---Split a string into an array of whole characters.
---@param text string
---@return string[]
local function toChars(text)
    local out = {}
    for c in Glyphs.chars(text) do out[#out + 1] = c end
    return out
end

local function clampNumber(v, lo, hi, fallback)
    if type(v) ~= 'number' or v ~= v then return fallback end   -- v ~= v catches NaN
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

---Strip anything the alphabet cannot render, collapse runs of spaces, and trim.
---Returns the cleaned string, which may be empty.
---@param text any
---@return string
function Sign.sanitiseText(text)
    if type(text) ~= 'string' then return '' end
    if not utf8.len(text) then return '' end        -- reject malformed UTF-8 outright
    -- Normalise CRLF first: a textarea on Windows sends \r\n, and letting the \r
    -- through would leave every row after the first with a stray unrenderable
    -- character that still eats a slot in the per-character colour string.
    text = text:gsub('\r\n', '\n'):gsub('\r', '\n')

    local out = {}
    for c in Glyphs.chars(text) do
        if Glyphs.META[c] or c == ' ' or c == '\n' then out[#out + 1] = c end
    end

    -- Collapse runs of spaces per row, then trim each row. Done row-wise because a
    -- single %s+ collapse would eat the newlines along with the spaces.
    local rows = {}
    for line in (table.concat(out) .. '\n'):gmatch('([^\n]*)\n') do
        rows[#rows + 1] = (line:gsub(' +', ' '):gsub('^ +', ''):gsub(' +$', ''))
    end
    -- Drop trailing blank rows so a stray Enter at the end is not a row.
    while #rows > 1 and rows[#rows] == '' do rows[#rows] = nil end
    return table.concat(rows, '\n')
end

---Coerce an arbitrary (possibly hostile) payload into a legal sign record.
---The NUI applies the same limits for feedback, but this is the authority.
---@param raw table
---@return table|nil record, string|nil reason
function Sign.normalise(raw)
    if type(raw) ~= 'table' then return nil, 'malformed' end
    local L = config.Limits
    local text = Sign.sanitiseText(raw.text)
    if text == '' then return nil, 'empty' end

    -- Clamp rows, then each row's length. Truncate by CHARACTER, not byte: #text on a
    -- string of arrows is triple the character count, and a byte-wise cut would slice
    -- a codepoint in half and produce invalid UTF-8.
    local rows = {}
    for line in (text .. '\n'):gmatch('([^\n]*)\n') do
        if #rows >= (L.maxRows or 1) then break end
        local chars = toChars(line)
        if #chars > L.maxLength then
            line = table.concat(chars, '', 1, L.maxLength)
        end
        rows[#rows + 1] = line
    end
    text = table.concat(rows, '\n')
    if text:gsub('\n', '') == '' then return nil, 'empty' end

    local colour = raw.colour
    if not COLOUR_SET[colour] then colour = config.Defaults.colour end

    -- Re-count after truncation so the per-character colours cannot outlive the text
    -- they describe.
    local colours = normaliseColours(raw.colours, #toChars(text))

    local style = raw.style
    if not STYLE_SET[style] then style = config.Defaults.style or 'painted' end

    local spin = clampNumber(raw.spin, 0.0, config.Limits.maxSpin or 180.0, 0.0)
    local anim = Anim.sanitise(raw.anim)
    local animSpeed = clampNumber(raw.animSpeed, Anim.MIN_SPEED, Anim.MAX_SPEED, Anim.DEFAULT_SPEED)

    return {
        text      = text,
        colour    = colour,
        colours   = colours,
        style     = style,
        anim      = anim,
        animSpeed = animSpeed,
        spin      = spin,
        size      = clampNumber(raw.size,      L.minSize,      L.maxSize,      config.Defaults.size),
        thickness = clampNumber(raw.thickness, L.minThickness, L.maxThickness, config.Defaults.thickness),
        tracking  = clampNumber(raw.tracking,  L.minTracking,  L.maxTracking,  config.Defaults.tracking),
        x         = clampNumber(raw.x, -10000.0, 10000.0, 0.0),
        y         = clampNumber(raw.y, -10000.0, 10000.0, 0.0),
        z         = clampNumber(raw.z, -500.0,   2000.0,  0.0),
        heading   = clampNumber(raw.heading, -720.0, 720.0, 0.0) % 360.0,
        -- How far away this sign stays spawned. Nil is meaningful and preserved: it
        -- means "whatever Config.RenderDistance is", which is what every sign placed
        -- before this slider existed stores, and what lets one config edit still move
        -- all of them at once.
        renderDistance = raw.renderDistance ~= nil
            and clampNumber(raw.renderDistance, 10.0, config.MaxRenderDistance or 400.0,
                config.RenderDistance)
            or nil,
    }
end

---Lay a sign out along its local X axis, centred on the anchor.
---
---Letters are spaced optically (glyph bounding box + tracking) rather than by the
---font's kerning pairs, which is how real channel-letter signage is set.
---
---Newlines split the text into rows, each centred on its own width and stacked
---symmetrically about the anchor. A single-row sign therefore lays out exactly as it
---always has, `rise` being 0 throughout -- which is what stops every sign already
---placed in the world from jumping the first time this runs.
---@param text string already sanitised
---@param size number cap height in metres
---@param tracking number gap between letters, in cap-height units
---@param colour string base palette colour name
---@param colours string|nil per-character palette digits (see normaliseColours)
---@param style string|nil "painted" (default) or "neon"
---@return table letters array of { char, model, colour, tint, offset, rise }, metres
---@return number width of the widest row, in metres
---@return number rows how many rows the text laid out into
function Sign.layout(text, size, tracking, colour, colours, style)
    local chars = toChars(text)

    -- Split into rows, remembering each character's index in the ORIGINAL string.
    -- `colours` is one digit per character of `text`, newlines included, so colours
    -- must be looked up by that original index or every row after the first is
    -- painted with the wrong letters' colours.
    local rows, row = {}, { chars = {}, at = {} }
    for i = 1, #chars do
        if chars[i] == '\n' then
            rows[#rows + 1] = row
            row = { chars = {}, at = {} }
        else
            row.chars[#row.chars + 1] = chars[i]
            row.at[#row.at + 1] = i
        end
    end
    rows[#rows + 1] = row

    local letters, widest = {}, 0.0
    -- Stack downward from the top so the block is centred on the anchor. With one row
    -- this is exactly 0, which is what keeps existing signs where they were placed.
    local top = (#rows - 1) * Sign.LINE / 2.0

    for r = 1, #rows do
        local rc, at = rows[r].chars, rows[r].at
        local n = #rc
        local advances, total = {}, 0.0
        for i = 1, n do
            local meta = Glyphs.META[rc[i]]
            local w = (rc[i] == ' ') and Glyphs.SPACE or (meta and meta.w or 0.0)
            advances[i] = w
            total = total + w
        end
        if n > 1 then total = total + tracking * (n - 1) end
        if total > widest then widest = total end

        -- Each row is centred on its own width, which is how stacked signage is set:
        -- centring the block as a whole would leave short rows hanging off to one side.
        local cursor = -total / 2.0
        local rise = (top - (r - 1) * Sign.LINE) * size
        for i = 1, n do
            local c = rc[i]
            if c ~= ' ' and Glyphs.META[c] then
                local col = Sign.colourAt(colour, colours, at[i])
                letters[#letters + 1] = {
                    char   = c,
                    colour = col,
                    -- The model carries the finish only. Colour rides alongside it as
                    -- a tint index, applied to the entity after it spawns.
                    model  = Glyphs.model(c, style),
                    tint   = Glyphs.tint(col),
                    offset = (cursor + advances[i] / 2.0) * size,
                    rise   = rise,
                }
            end
            cursor = cursor + advances[i] + tracking
        end
    end
    return letters, widest * size, #rows
end

---Total width in metres without building the letter list (for UI readouts).
---@return number
function Sign.width(text, size, tracking)
    local _, w = Sign.layout(text, size, tracking, config.Defaults.colour)
    return w
end

---Heading that makes a letter's lit face point from `at` toward `viewer`.
---
---The models face model -Y. An entity at heading h has forward (model +Y) =
---(-sin h, cos h), so the lit face points (sin h, -cos h). Solving that against the
---desired direction gives h = atan2(d.x, -d.y).
---@param atX number
---@param atY number
---@param viewerX number
---@param viewerY number
---@return number heading degrees
function Sign.headingToFace(atX, atY, viewerX, viewerY)
    local dx, dy = viewerX - atX, viewerY - atY
    if dx == 0.0 and dy == 0.0 then return 0.0 end
    return math.deg(math.atan(dx, -dy)) % 360.0
end

---Unit vector along which letters are laid out (the sign's local +X) for a heading.
---@param heading number degrees
---@return number rx, number ry
function Sign.rightVector(heading)
    local h = math.rad(heading)
    return math.cos(h), math.sin(h)
end

---Vertical extent of a laid-out sign above and below its baseline, in metres.
---@return number above, number below
function Sign.verticalExtent(text, size)
    local above, below, rows = 0.0, 0.0, 1
    for c in Glyphs.chars(text) do
        if c == '\n' then
            rows = rows + 1
        else
            local meta = Glyphs.META[c]
            if meta then
                if meta.top > above then above = meta.top end
                if meta.bot < below then below = meta.bot end
            end
        end
    end
    -- Rows stack symmetrically about the anchor, so a three-row sign reaches one full
    -- line height further up AND down than its tallest glyph alone. Without this the
    -- live preview fits the camera to a single row and crops the other two.
    local half = (rows - 1) * Sign.LINE / 2.0
    return (above + half) * size, (below - half) * size
end

return Sign
