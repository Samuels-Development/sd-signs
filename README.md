<div align="center">

# sd-signs

**3D signs for FiveM. Type it, colour it, place it.**
Real extruded letter props — not a texture on a plane — in 129 glyphs, ten colours and a
matte or neon finish. Up to three rows of text. Size, depth and letter spacing are sliders,
every letter can be its own colour, and the whole sign can pulse, cycle, wave or spin. Drag it
into place by aim or with a gizmo, saved to the database, admin-gated by default.

Colour is a runtime tint rather than baked geometry, so the whole palette ships in **258 models
and about 5 MB** — and a ten-colour animation costs no more entities than a static sign.

If sd-signs is useful to you, please ⭐ the repo. Issues and pull requests are always welcome.

[![Release](https://img.shields.io/github/v/release/Samuels-Development/sd-signs?label=Release&logo=github)](https://github.com/Samuels-Development/sd-signs/releases)
[![Stars](https://img.shields.io/github/stars/Samuels-Development/sd-signs?label=Stars&logo=github)](https://github.com/Samuels-Development/sd-signs)
[![Discord](https://img.shields.io/discord/842045164951437383?label=Discord&logo=discord&logoColor=white)](https://discord.gg/FzPehMQaBQ)
[![License](https://img.shields.io/badge/License-GPL--3.0-94DD0C)](LICENSE)

![Requires](https://img.shields.io/badge/Requires-ox__lib%20%2B%20oxmysql-ef4444)
![Framework](https://img.shields.io/badge/Framework-none%20required-22c55e)
![Database](https://img.shields.io/badge/Database-MySQL-f59e0b)

[**Store**](https://fivem.samueldev.shop) · [**Documentation**](https://docs.samueldev.shop) · [**Discord**](https://discord.gg/FzPehMQaBQ)

</div>

---

## Preview

<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/686296e5-bed1-4ae6-8e0c-5a7a5c4146d1" />
<img width="1920" height="1080" alt="FiveM_b3258_GTAProcess_4l8j3n6xI2" src="https://github.com/user-attachments/assets/a371f124-cb67-4524-93e2-a01ae0773fde" />
<img width="1920" height="1080" alt="FiveM_b3258_GTAProcess_1JvNraJcx5" src="https://github.com/user-attachments/assets/fc0c0881-08f2-45c8-b76b-1b46cc2a3bac" />
<img width="1920" height="1080" alt="FiveM_b3258_GTAProcess_K8DZ4PXWJ2" src="https://github.com/user-attachments/assets/ba9efac7-22a1-4800-8f67-5da557ed68ea" />
<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/17a0f663-7a4c-430f-a8a3-5b3cb5cd5dac" />
<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/742d523b-54ee-4ea6-9802-458cdbc5f9e4" />



## What it is

A sign builder. You type text into a panel, it appears floating in front of you as you type,
you tune it, and then you place it against a wall with a raycast. It stays there, for everyone,
across restarts.

The letters are **streamed props**, one game object per character. That is what makes them
read as real signage: they catch light, cast shadows, have a visible depth and a dark return
down the sides, and you can walk around them. A 24-character sign is 24 entities, which is why
there is a render distance and a length cap.

| | |
|---|---|
| **129 glyphs** | `A–Z`, `a–z`, `0–9` and 67 symbols — punctuation, brackets, currency, arrows, fractions and maths |
| **10 colours** | white, red, orange, amber, yellow, green, cyan, blue, purple, pink |
| **2 finishes** | `painted` (matte) or `neon` (emissive face that glows at night) |
| **Up to 3 rows** | press Enter for a new row; rows stack and centre on each other |
| **Per-letter colour** | click any letter in the preview and recolour just that one |
| **Animation** | `gradient`, `cycle`, `wave`, `chase`, `pulse`, or off |
| **Spin** | 0–180°/s about the vertical axis |
| **Size** | 0.2 m to 120 m cap height — a doorway plaque or a letter half the height of the Maze Bank |
| **Per-sign visibility** | each sign carries its own render distance, up to ~2 miles |
| **Two placement modes** | aim-and-scroll, or drag handles via the optional [object_gizmo](https://github.com/DemiAutomatic/object_gizmo) |
| **Live preview** | the real sign, floating in the world, updating as you type |
| **Admin overview** | every placed sign, with preview, highlight, teleport, edit and delete |

## Requirements

- [ox_lib](https://github.com/communityox/ox_lib)
- [oxmysql](https://github.com/communityox/oxmysql)

**No framework required.** There is no ESX/QB/Qbox bridge and none is needed — the resource
resolves players through natives and stores ownership against the licence identifier, so it runs
the same on any framework or on none.

## Installation

1. Download the latest release zip from [Releases](https://github.com/Samuels-Development/sd-signs/releases)
   and drop `sd-signs` into your resources folder.
2. `ensure sd-signs` in your `server.cfg`, after `ox_lib` and `oxmysql`.
3. Grant yourself permission:

   ```cfg
   add_ace group.admin sd-signs.build allow
   ```

   txAdmin admins already hold `group.admin`, so they are covered.
4. Restart. The table is created on first start; there is no SQL file to import.

> [!IMPORTANT]
> Use a release zip rather than a source download. The NUI is not committed to this repo —
> the release workflow builds it from `web/src` and packages it — so a clone of `main` has no
> `web/build` and the panel will not open until you run `npm ci && npm run build` in `web/`.

## Commands

| Command | What it does |
|---|---|
| `/sign` | Opens the builder. Tabs between **Build** and **Placed**. |
| `/signs` | Opens the same panel straight on the placed-signs overview. |
| `/signremove` | Deletes the nearest sign within 12 m. |

All three are gated behind `Config.Ace`.

## Configuration

Everything lives in [`configs/config.lua`](configs/config.lua) and is commented in place.
The parts worth knowing about:

| Setting | Default | Notes |
|---|---|---|
| `Config.Ace` | `'sd-signs.build'` | Set to `false` to open sign building to everyone. Not recommended — signs are persistent, visible to everyone and cost entity budget. |
| `Config.Limits.maxLength` | `24` | Characters **per row**. Each one is an entity, so a full three-row sign is up to 72. |
| `Config.Limits.maxRows` | `3` | Rows in one sign. Stored as newlines in the sign's text. |
| `Config.Limits.maxSize` | `120.0` | Cap height in metres at the top of the slider. |
| `Config.Limits.maxPerPlayer` | `40` | Signs one licence may own. `nil` for unlimited. |
| `Config.RenderDistance` | `120.0` | **Default** for new signs — each sign then stores its own. Signs placed before that existed fall back to this, so one edit still moves them all. |
| `Config.MaxRenderDistance` | `3200.0` | Top of the per-sign visibility slider. Going higher also needs `LOD_DIST` raised in `export_fivem.py` and the `.ytyp` regenerated, or the game stops drawing letters it is still streaming. |
| `Config.EntityBudget` | `900` | Ceiling on letter entities across every spawned sign. Signs are considered nearest-first, so the farthest go unspawned at the cap. |
| `Config.Animation.letterBudget` | `600` | How many letters get re-tinted per tick. A CPU budget, not an object one — animation costs no extra entities. |
| `Config.Placement.default` | `'raycast'` | `'gizmo'` to start in gizmo mode. Falls back to raycast when `object_gizmo` is not running. |
| `Config.Placement.allowSwitch` | `true` | `false` hides the mode toggle and pins everyone to the default. |
| `Config.Persist` | `true` | `false` keeps signs in memory only, which is handy while testing. |

Server-side limits are enforced independently of the UI. The panel mirrors them for
convenience, but every submitted sign is re-clamped in `shared/sign.lua` before it is stored —
the NUI is not a security boundary.

## How the props work

129 glyphs in two finishes is **258 models, about 5 MB** — and that covers all ten colours,
because colour is not in the geometry.

Both finishes use a GTA *tint* shader (`default_tnt.sps`, `emissive_tnt.sps`) carrying a
small palette texture with one row per colour. The game picks the row per entity:

```lua
SetObjectTextureVariation(entity, 7)   -- blue, on any glyph
```

So "red A" and "blue A" are the same streamed model, told apart by one integer at spawn
time. Baking colour into each model instead would mean 2580 models and ~44 MB.

Three consequences worth knowing:

- **Animation is free in entity terms.** A sign is one object per letter whether it is
  static or running a ten-colour wave — animating just writes a new tint index to the same
  entities. `Config.Animation.letterBudget` caps how many letters are re-tinted per tick,
  which is a CPU budget, not an object one.
- **Entity count scales with sign density, not with the palette.** `Config.RenderDistance`
  bounds how far signs spawn and `Config.EntityBudget` bounds how many letters exist at
  once; past that ceiling the farthest signs stay unspawned.
- **Signs have no collision.** GTA scales an entity's visual through its matrix but *not* its
  collision mesh, so a scaled-up sign would be visually large and physically letter-sized.
  A sign you can walk through is the honest option.

## Regenerating the props

You do not need Blender to run this resource — the props ship in `stream/`. The toolchain in
[`assets/blender/`](assets/blender) is there if you want to change the font, the palette or the
letter depth. It is a four-step pipeline:

| Step | Run in | Produces |
|---|---|---|
| `build_alphabet3d.py` | Blender | the 129 glyph meshes and the palette texture |
| `measure_glyphs.py` | Blender | `glyph_metrics.json` — advance widths measured off the real meshes |
| `gen_glyphs_lua.js` | node | `shared/glyphs.lua` |
| `export_fivem.py` | Blender ([Sollumz](https://github.com/Sollumz/Sollumz)) | `stream/*.ydr` and the `.ytyp` |

The scripts resolve their own location, so a clone needs no path editing -- open the two
Blender ones from the Scripting workspace and run them in order. Set `A3D_BUILD_DIR` if you
want the intermediates written somewhere other than `assets/blender/build`. See [`assets/blender/README.md`](assets/blender/README.md) for the gotchas — there are
several, and most of them fail silently.

Changing the font is supported but not free: it changes every advance width, so all four steps
have to be re-run, and the replacement must cover all 129 glyphs and be a *static* Bold. It is
also worth changing the `.sa-preview__text` font stack in `web/src/styles.css` (and `CAP_PER_EM` in `web/src/components/SignPreview.tsx`) to match, or the panel
preview quietly stops agreeing with what actually gets placed.

## Credits

The letters are built from **[Montserrat](https://github.com/JulietaUla/Montserrat)** Bold by
Julieta Ulanovsky and contributors, used under the
[SIL Open Font License 1.1](assets/blender/fonts/OFL.txt). The font is included with the
toolchain so the props are reproducible.

## License

[GPL-3.0](LICENSE).
