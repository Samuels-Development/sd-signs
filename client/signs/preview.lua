---@type table sd-signs config root (configs/config.lua).
local config  = require 'configs.config'
---@type table Sign geometry + validation (shared/sign.lua).
local Sign    = require 'shared.sign'
---@type table Colour effect maths (shared/anim.lua).
local Anim    = require 'shared.anim'
---@type table Turns a sign record into entities (client/signs/builder.lua).
local Builder = require 'client.signs.builder'

---A live sign floating in front of the camera while the builder is open, so size,
---thickness, colour and effect can be judged against the world rather than guessed
---from a flat panel.
local Preview = {}

---@type table|nil built payload
local built
---@type table|nil the record it was built from
local shown
---@type boolean
local visible = false

---Where the preview should sit for a sign of this width.
---
---Distance is derived from the camera FOV so the sign fills a consistent slice of the
---screen at any size -- a 6 m sign parked at a fixed distance would be off-screen,
---and a 0.2 m one invisible. It is also nudged left, because the panel covers the
---right of the screen.
---@param width number sign width in metres
---@param above number extent above the baseline, metres
---@param below number extent below the baseline, metres
---@return vector3 position, number heading
local function anchor(width, above, below)
    local cam = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    local rz, rx = math.rad(rot.z), math.rad(rot.x)
    local flat = math.abs(math.cos(rx))
    local fwd = vec3(-math.sin(rz) * flat, math.cos(rz) * flat, math.sin(rx))
    local right = vec3(math.cos(rz), math.sin(rz), 0.0)

    local fov = GetGameplayCamFov()
    local halfFov = math.rad(fov * 0.5)
    local cfg = config.LivePreview

    -- Fit the wider of the two axes, then back off by the margin.
    local height = math.max(0.01, above - below)
    local byWidth = (width * 0.5) / math.max(0.01, math.tan(halfFov) * GetAspectRatio(false))
    local byHeight = (height * 0.5) / math.max(0.01, math.tan(halfFov))
    local dist = math.max(byWidth, byHeight) * cfg.margin
    dist = math.max(cfg.minDistance, math.min(cfg.maxDistance, dist))

    local viewHalfWidth = dist * math.tan(halfFov) * GetAspectRatio(false)
    local pos = cam + fwd * dist - right * (viewHalfWidth * cfg.lateralShift)

    -- The glyph origin is on the baseline, so drop it by half the vertical extent
    -- to centre the sign on the camera rather than hanging it below.
    pos = vec3(pos.x, pos.y, pos.z - (above + below) * 0.5)

    return pos, Sign.headingToFace(pos.x, pos.y, cam.x, cam.y)
end

---Show (or update) the preview for a draft record.
---@param draft table
function Preview.show(draft)
    if not config.LivePreview.enabled then return end
    if type(draft) ~= 'table' then return end

    local record = Sign.normalise(draft)
    if not record then
        Preview.hide()
        return
    end

    local _, width = Sign.layout(record.text, record.size, record.tracking,
        record.colour, record.colours, record.style)
    local above, below = Sign.verticalExtent(record.text, record.size)
    local pos, heading = anchor(width, above, below)
    record.x, record.y, record.z, record.heading = pos.x, pos.y, pos.z, heading

    -- Only respawn when the model set actually changes. Text/colour/finish/effect pick
    -- different props; size, thickness and tracking just move what is already there,
    -- and rebuilding on every slider tick would churn entities for nothing.
    if built and not Builder.needsRebuild(shown, record) then
        Builder.reposition(built, record)
        shown = record
        visible = true
        return
    end

    Builder.destroy(built)
    built = Builder.build(record, false)
    shown = record
    visible = true
end

---Tear the preview down.
function Preview.hide()
    Builder.destroy(built)
    built, shown, visible = nil, nil, false
end

-- Keep it glued to the camera and animated while it is up. The camera can still be
-- rotated with the menu open, so the anchor has to be recomputed, not set once.
CreateThread(function()
    while true do
        if visible and built and shown then
            local _, width = Sign.layout(shown.text, shown.size, shown.tracking,
                shown.colour, shown.colours, shown.style)
            local above, below = Sign.verticalExtent(shown.text, shown.size)
            local pos, heading = anchor(width, above, below)
            shown.x, shown.y, shown.z, shown.heading = pos.x, pos.y, pos.z, heading
            local spin = shown.spin or 0
            Builder.reposition(built, shown,
                spin > 0 and (heading + spin * (GetGameTimer() / 1000.0)) % 360.0 or nil)
            if Anim.isDynamic(Anim.sanitise(shown.anim)) then
                Builder.tint(built, shown, GetGameTimer() / 1000.0)
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name == cache.resource then Preview.hide() end
end)

return Preview
