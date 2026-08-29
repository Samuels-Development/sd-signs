---@class SdSignsConfig
local Config = {}

--- Print debug lines to the console (shared/log.lua honours this). Leave off in
--- production: info, warnings and errors are printed regardless.
Config.Debug = false

--- Command that opens the sign builder.
Config.Command = 'sign'

--- ACE permission required to build, remove or review signs. Set to false to open it
--- up to everyone -- not recommended: signs are persistent, visible to every player,
--- cost entity budget, and arbitrary text placed anywhere is a griefing vector.
---
--- Grant it in server.cfg:
---   add_ace group.admin sd-signs.build allow
---
--- txAdmin's own admins are covered too: they get `group.admin` by default.
Config.Ace = 'sd-signs.build'

--- Command that opens the placed-signs overview (list / teleport / delete).
Config.OverviewCommand = 'signs'

--- Persist placed signs to the database. When false, signs live only until the
--- resource restarts, which is handy while testing.
Config.Persist = true

--- Limits the server enforces on every submitted sign. The NUI mirrors these, but
--- the server clamps independently -- the UI is a convenience, not a security boundary.
Config.Limits = {
    --- Max characters in one ROW of a sign. Each character is a separate game entity,
    --- so this is really an entity budget: a 24-char row is 24 objects, and a full
    --- three-row sign is up to 72.
    maxLength = 24,
    --- Max rows in one sign. Rows are separated by newlines inside the sign's text and
    --- are stacked and centred on the anchor, so a one-row sign sits exactly where a
    --- one-row sign has always sat.
    maxRows = 3,
    --- Cap height in metres. 1.0 == the source models' native size.
    ---
    --- Cap height in metres, for the slider's NORMAL range. 10 m is already a tall
    --- letter -- most signage, from a doorway plaque to a shopfront to the side of a
    --- building, lives well below it -- so this is where the slider spends its travel.
    minSize = 0.2,
    maxSize = 10.0,

    --- Ceiling once the builder's **Ultra** toggle is on, in metres.
    ---
    --- Kept behind a toggle because stretching one slider to 120 m makes the useful
    --- range a thumbnail's worth of travel at the far left, and almost every sign is
    --- built in that range. For scale: the Hollywood sign's letters are about 13.7 m
    --- and the Maze Bank tower is roughly 200 m, so 120 m caps is a letter over half
    --- the height of the tallest building in Los Santos.
    ---
    --- Size costs nothing extra: a sign is one entity per letter whatever its scale,
    --- and collision is off. Two things do scale though, and both have their own
    --- setting:
    ---   * a 24-character sign at 120 m caps is roughly 2.8 km wide, so letters can
    ---     end up far apart -- give it a matching per-sign render distance or it will
    ---     pop in while you are standing inside it;
    ---   * the live preview can only back off as far as LivePreview.maxDistance, so
    ---     past a point it shows you the middle of the sign rather than all of it.
    ---
    --- The server clamps to THIS value, not to maxSize: the toggle is a UI convenience
    --- and the server has no idea whether it was on, so it can only enforce the
    --- absolute ceiling. Set both to the same number to remove ultra sizes entirely.
    maxSizeUltra = 120.0,
    --- Multiplier on the models' 0.12 m depth.
    minThickness = 0.25,
    maxThickness = 8.0,
    --- Gap between letters, expressed in cap-height units so it scales with the sign:
    --- a tracking of 0.12 on a 2 m sign is a 0.24 m gap. Negative values tighten the
    --- letters and eventually overlap them, which is useful for logotypes.
    --- The builder's slider is driven by these, so widening them widens the UI.
    minTracking = -0.30,
    maxTracking = 1.50,
    --- Rotation speed in degrees per second. 0 is a static sign.
    maxSpin = 180.0,
    --- Signs one player may own at once (nil = unlimited).
    maxPerPlayer = 40,
}

--- Defaults the builder opens with.
Config.Defaults = {
    text      = 'LOS SANTOS',
    colour    = 'white',
    --- 'painted' (matte) or 'neon' (emissive face, glows at night).
    style     = 'painted',
    --- Colour animation: off | gradient | cycle | wave | chase | pulse.
    anim      = 'off',
    --- Animation steps per second.
    animSpeed = 2.0,
    --- Degrees per second of rotation about the vertical axis. 0 = static.
    spin      = 0.0,
    size      = 1.0,
    thickness = 1.0,
    tracking  = 0.12,
}

--- How far from the player a sign's letters stay spawned, in metres. Signs beyond
--- this are despawned and rebuilt on approach, so a map full of signs costs no
--- entities.
---
--- This is the DEFAULT for new signs. Each sign stores its own distance, so a stadium
--- sign can be readable from far further than a shop doorway; signs placed before the
--- per-sign slider existed have no stored value and fall back to this.
Config.RenderDistance = 120.0

--- Upper bound on the per-sign slider, in metres. ~3200 m is a little over two miles.
---
--- Raising it does not raise the entity cost on its own -- Config.EntityBudget still
--- caps how many letters exist at once, and past that ceiling the farthest signs
--- simply stay unspawned.
---
--- Raising it ABOVE 3200 does nothing on its own. The archetypes in stream/sd_a3d.ytyp
--- carry a LOD distance of 3200 m, and past that the game stops drawing a letter even
--- though its entity still exists -- a sign set further would spawn and stay invisible.
--- To go beyond, raise LOD_DIST in assets/blender/export_fivem.py and re-run write_ytyp().
Config.MaxRenderDistance = 3200.0

--- Hard ceiling on letter entities across every spawned sign at once.
---
--- RenderDistance bounds how FAR signs spawn, not how MANY: a plaza with dozens of
--- long signs inside 120 m is the one layout that can run the entity count up, and
--- the symptom is other props failing to spawn rather than a framerate drop. GTA's
--- object pool is roughly 2300 and shared with the whole map, so this leaves ample
--- headroom for everything that is not a sign.
---
--- Signs are considered nearest-first, so what goes unspawned at the ceiling is
--- always the farthest. Set to nil to disable the cap.
Config.EntityBudget = 900

--- Animation costs no extra entities: colour is a per-entity tint index, so an
--- animated sign is exactly the same objects as a static one and only the work of
--- rewriting those tints is budgeted here.
Config.Animation = {
    --- Rotation refreshes per second. Higher than the colour rate because a
    --- turning sign needs to look smooth, not stepped.
    spinRate = 30,
    --- Refreshes per second. The palette has ten discrete colours, so there is
    --- nothing to gain from running this at frame rate.
    rate = 15,
    --- Only animate within this range. Beyond it the sign still renders, in its
    --- base colour, as a single entity per letter.
    distance = 70.0,
    --- Hard ceiling on how many LETTERS are being re-tinted per tick across all
    --- signs at once. A 10-letter wave counts 10, not 100 -- it used to cost one
    --- entity per letter per colour, and this was an entity budget of 420.
    --- Signs are considered nearest-first, so the farthest ones stop animating and
    --- keep rendering in their resting colours.
    letterBudget = 600,
}

--- The live sign that floats in front of you while the builder is open.
Config.LivePreview = {
    enabled = true,
    --- Back-off multiplier once the sign has been fitted to the FOV. 1.0 fills the
    --- frame exactly; higher leaves air around it.
    margin = 1.55,
    --- Shift left as a fraction of half the view width, to clear the panel.
    lateralShift = 0.34,
    minDistance = 2.0,
    --- How far the preview may back off to fit the sign in view. This has to scale
    --- with Config.Limits.maxSize: the preview computes the distance that fits the
    --- sign to the FOV and then clamps it here, so a cap set too low silently crops
    --- big signs instead of showing them. At 45 m -- the old value -- even a ten
    --- character sign at 6 m caps was already being cut off.
    ---
    --- The very largest signs still overflow: fitting 24 characters at 30 m caps would
    --- need roughly 670 m, and a preview that far away is more useful cropped than
    --- correct. Place it and look at the real thing at that point.
    maxDistance = 400.0,
}

--- Placement raycast reach, in metres, from the camera.
Config.PlaceReach = 25.0

--- How a sign is positioned when placing a new one or moving an existing one.
---
--- 'gizmo' needs the optional `object_gizmo` resource. It is deliberately NOT a
--- fxmanifest dependency -- that would make every server install it -- so it is
--- detected at runtime and quietly falls back to 'raycast' when it is not started.
---
--- The gizmo only ever yaws a sign. It can tilt an entity on all three axes, but a
--- sign record stores a single heading, so pitch and roll are held at zero while you
--- drag rather than letting you tilt something that would snap flat on confirm.
Config.Placement = {
    --- 'raycast' (camera aim + scroll to turn) or 'gizmo' (drag handles in the world).
    default = 'raycast',
    --- Let players switch mode from the builder. false pins everyone to `default`.
    allowSwitch = true,
}

--- Letters are decorative. Collision at any scale would be wrong anyway: GTA scales
--- the visual via the entity matrix but NOT the collision mesh, so a scaled-up sign
--- would be visually large and physically letter-sized. Honest non-solid beats that.
Config.Collision = false

return Config
