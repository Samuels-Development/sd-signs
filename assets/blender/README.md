# Alphabet 3D — emissive channel letters

A–Z, a–z, 0–9, 67 symbols and 62 accented letters as extruded 3D "channel letter"
props, in 10 emissive colours.

**1,910 character/colour variants, built from 191 meshes, 2 materials and 1 texture.**

![chart](preview_chart.png)
![grid](preview_grid.png)

---

## The trick: colour is a per-object property, not geometry

The obvious way to get "a blue A and a green B" is 1910 models, or at least 191 models ×
10 materials. Both are wasteful. Instead:

1. All 10 colours live in **one 512×512 texture** (`textures/alphabet_palette.png`),
   as a 4×4 grid of flat colour cells.
2. Every glyph's front faces have their UVs parked in a **tiny square inside cell 0**.
   The glyph is never actually unwrapped — it just samples one flat colour.
3. The material reads an **object custom property `color_id`** and uses a `Mapping`
   node to *shift* that UV square onto whichever cell you asked for.

Because the shift happens in the shader and not in the mesh, two objects can share the
exact same mesh datablock and still render different colours. Every variant is a
**linked duplicate**.

The result: `alphabet3d.blend` holds ~1,420 objects and weighs well under a megabyte.

```
191 glyph meshes   ── shared by ──▶  1910 showcase objects + demo objects
  1 palette texture                   (each carries only an int: color_id)
  2 live materials   (+2 baked, for export)
```

### Palette

| id | name   | sRGB      | id | name   | sRGB      |
|----|--------|-----------|----|--------|-----------|
| 0  | white  | `#FFFFFF` | 5  | green  | `#29F240` |
| 1  | red    | `#FF1A14` | 6  | cyan   | `#1AE6FF` |
| 2  | orange | `#FF610D` | 7  | blue   | `#1A59FF` |
| 3  | amber  | `#FFA814` | 8  | purple | `#8C33FF` |
| 4  | yellow | `#FFF026` | 9  | pink   | `#FF26A6` |

Cells 10 and 11 are the letter **returns** (the extruded sides), selected by a second
property `return_style` — `0` = dark (default), `1` = light grey. Cells 12–15 are spare;
add more colours by extending `PALETTE` in the script, no geometry changes needed.

---

## Files

| Path | What |
|---|---|
| `alphabet3d.blend` | The working file. Open this. |
| `build_alphabet3d.py` | **1.** Rebuilds the 191 glyph meshes, palette and materials. |
| `measure_glyphs.py` | **2.** Measures the built meshes into `glyph_metrics.json`. |
| `gen_glyphs_lua.js` | **3.** Turns those metrics into `sd-signs/shared/glyphs.lua` (node, not Blender). |
| `export_fivem.py` | **4.** `main()` exports all 382 `.ydr` + the `.ytyp` and ships them to `stream/`. |
| `fonts/Montserrat-Bold.ttf` | The source face, with its `OFL.txt`. |
| `glyph_metrics.json` | Generated. Advance widths in cap-height units — the contract between the props and the in-game layout. |
| `textures/alphabet_palette.png` | The single 512×512 palette. Also packed into the .blend. |
| `export/alphabet_<colour>.glb` | All 191 glyphs in one colour, ×10 files. Only used for the render previews. |
| `preview_hero.png` `preview_chart.png` `preview_grid.png` | Rendered previews. |
| `preview_back.png` `preview_edge.png` | Rear and edge-on views (see *Solid geometry*). |

### Collections in the .blend

- **`AL_Master`** — the 191 source glyphs. This is the actual model library.
- **`AL_Showcase`** — every variant, laid out as a 191 × 10 grid (near `x = -105`).
- **`AL_Demo`** — a small sign showing mixed per-letter colours.

---

## Using it

In Blender's Scripting tab, with `build_alphabet3d.py` open:

```python
spawn("A", "blue", location=(0, 0, 0))       # one letter, linked to the master mesh

set_colour(bpy.data.objects["AL_U_A"], "pink")          # recolour in place, O(1)
set_colour(obj, "cyan", return_style=1)                 # + light returns

spawn_text("OPEN 24/7", colour="red", location=(0, 0, 3))

spawn_text("Qbox", per_char_colours=["cyan", "pink", "amber", "green"])
```

`spawn_text` spaces letters **optically** (bounding box + tracking), which is how real
channel-letter signage is set, rather than by the font's kerning pairs.

> Setting `obj["color_id"]` / `obj["return_style"]` **directly** needs an
> `obj.update_tag()` afterwards, or the render keeps the old colour — EEVEE caches the
> per-object attribute buffer. `set_colour()` does this for you.

### Solid geometry

These are closed, watertight solids — not flat planes or single-sided cards. Every glyph
has a real back face and real extruded sides:

![back](preview_back.png)
![edge](preview_edge.png)

Verified per mesh: **0 boundary edges, 0 non-manifold edges, positive signed volume**, and
the back-face polygon count exactly matches the front (symmetric extrusion). e.g. `S` is
226 front / 226 back / 342 side polygons, volume 0.073 m³.

The front face gets the emissive material; **the back and sides both get the return
material**, matching how real channel letters are built (lit face, dark metal returns).
`preview_back.png` above uses `return_style = 1` (light returns) so the geometry reads —
the default `0` is near-black by design.

### Conventions

- **Cap height of `H` is exactly 1.000 m.** Scale the whole set to taste. The bevel adds
  a ~0.010 m skirt, so flat-topped letters measure 1.020 m overall.
- **Origin is on the baseline, horizontally centred** — so letters line up on a common
  baseline just by sharing a Z, and descenders (`g`, `j`, `p`, `q`, `y`) hang below it
  correctly.
- **Letters face −Y** (Blender's front view, numpad 1) and the **back face sits exactly
  on the Y = 0 plane**, so they mount flush against a wall with no offset fiddling.
- Depth is 0.12 m + 0.02 m of bevel = 0.140 m total.
- ~1 300 tris per glyph for the base Latin set (accented glyphs run higher — `Å` and the
  tilde caps carry the most curve). Raise `RES_U`
  in the config for smoother curves if you need hero-quality closeups.

### Naming

`AL_U_A` (uppercase), `AL_L_A` (lowercase a), `AL_D_0` (digit). The `U_`/`L_`/`D_` tag
exists because Windows filenames are case-insensitive — `A.glb` and `a.glb` would
collide on a per-glyph export, `U_A.glb` and `L_A.glb` don't.

Accented letters take an ASCII slug from `ACCENTS` but **keep** the case tag, because
they have both cases and collide exactly like `A`/`a`: `AL_U_ADIAER` / `AL_L_ADIAER`,
exported as `sd_a3d_uadiaer` / `sd_a3d_ladiaer`. The slug itself is case-free, so the
pair shares one entry in the table. This is why accents are a separate dict from
`SYMBOLS` rather than more entries in it — a symbol resolves to `AL_S_<SLUG>` and has
no case to preserve, so routing `Ä` and `ä` through it would collapse them into one
name and silently drop a mesh.

`ß` and `ÿ` have no uppercase inside Latin-1 (`ẞ` and `Ÿ` live elsewhere), so they only
ever produce an `L_` name. No special case is needed: `'ß'.islower()` is already true.

---

## Exports

`export/*.glb` holds one file per colour, each containing all 191 glyphs laid out as a
readable chart. Exported formats can't carry Blender object-attributes, so
`bake_mesh()` writes the palette offset into real UVs and swaps in the two
`*_Baked` materials. The texture is embedded in each GLB with `NEAREST` filtering and
`CLAMP_TO_EDGE`, so the flat cells can never bleed into each other at any mip level.

For a single asset per file:

```python
export_single("A", "blue", r"...\A_blue.glb")
```

### FiveM props

`export_fivem.py` builds the whole set as Sollumz `.ydr` drawables plus one `.ytyp`
archetype file, shipped into the `sd-alphabet` resource's `stream/` folder.

```python
E = runpy.run_path(r"...export_fivem.py")
E["export_style"]("neon")   # every glyph in one finish, all colours
E["write_ytyp"]()            # one .ytyp covering everything exported so far
E["ship"]()                  # copy .ydr/.ytyp into the resource
```

Model names are `sd_a3d_<tag><char-or-slug>[_neon]`, e.g. `sd_a3d_ua`, `sd_a3d_lg_neon`,
`sd_a3d_squest`. Symbols use an ASCII slug because a GTA model name may only contain
lowercase letters, digits and underscores.

### Colour is a tint index, not geometry

Blender gets 1910 variants from 191 meshes by reading an object property in the shader.
GTA cannot read Blender custom attributes — but it has its own version of the same idea,
so the trick survives the export rather than being baked away.

Both finishes use a **`_tnt` shader** (`default_tnt.sps`, `emissive_tnt.sps`) carrying a
second texture, `textures/alphabet_tint.dds`. The shader looks that texture up at
**(column = vertex colour red, row = the entity's tint index)**, and the game sets the
row per entity:

```lua
SetObjectTextureVariation(entity, 7)   -- blue, on any glyph, at no extra cost
```

So one `.ydr` per glyph per finish covers the whole palette: **382 models, ~8 MB**. Baking
colour into UVs instead would need 3820 models and ~65 MB, and would make an animated sign
cost one entity per letter *per colour* rather than one per letter.

Adding a colour is now editing `PALETTE` and re-running — no geometry changes, and the
other colours do not need re-exporting.

Four things that are NOT true of the GTA build:

- **The tint palette must stay uncompressed.** A DXT1 block is 4×4 pixels, so it spans
  four rows — four tint indices — and compressing it blends them into each other.
  `write_tint_dds()` writes raw A8R8G8B8 for this reason. The *diffuse* palette is still
  DXT1, where 4×4 blocks sit safely inside one flat cell.
- **The face must sample white.** The shader multiplies diffuse by the tint colour, so
  `build_drawable` bakes every glyph against the white cell. Any other cell tints a
  colour that is already coloured.
- **The `_tnt` shaders read `Color 0`, not `Color 1`.** Only the three `trees_*_tnt`
  shaders use `Color 1`. Meshes carry both, because the returns' `default.sps` still
  wants `Color 1` and renders black without it.
- **Never `bpy.data.images.remove()` the tint palette.** Both finishes' materials point
  at the same image, and removing a datablock nulls *every* reference to it, not just
  the caller's. A `_tnt` face with no palette renders **black** — silently, with no
  export warning, and only in whichever finish happened to be built first. This shipped
  once: the painted set went out black while neon looked perfect. `tint_dds()` now
  refreshes the image in place, and `face_material()` re-wires its samplers on every
  call (cache hits included) and raises if either is left unassigned.
- The lit face points model **-Y**. At entity heading 0 that faces world south, so a
  camera placed south of a sign sees the *front*. Spinning it 180 shows the dark returns
  and looks exactly like "the texture failed to load".

Only the **face** is tinted. The returns keep a plain `default.sps` sampling their own
dark cell, which is what preserves the lit-face / dark-metal look without spending a
palette row on it.

---

## Config

Everything is at the top of `build_alphabet3d.py`: `FONT_PATH`, `CAP_H`, `DEPTH`,
`BEVEL`, `RES_U`, `EMISSION`, and the `PALETTE` list. Re-run `main()` to rebuild.

> **Font licence:** built with **Montserrat Bold**, under the
> [SIL Open Font License 1.1](fonts/OFL.txt). The OFL permits redistributing derived
> artwork, which is what these meshes are — glyph outlines end up embedded in every
> model, so a system font such as Arial could not be published this way.
>
> Replacing it has three requirements, and two of them fail silently:
>
> 1. **All 191 glyphs.** Probe the font's `cmap` first — Roboto Bold, for one, has no
>    left or right arrow, and Blender exports a missing glyph as a `.notdef` box
>    rather than complaining.
> 2. **A *static* Bold.** Blender loads a variable font's default instance, which is
>    Regular, so a `Montserrat[wght].ttf` would quietly give you thin letters.
> 3. **Re-run the whole pipeline.** A different face means different advance widths,
>    so `glyph_metrics.json`, `shared/glyphs.lua` and all 382 `.ydr` go stale.

---

## Gotchas found while building this

Four silent failures, all of which produce *plausible-looking* wrong output:

1. **`image.pixels` is not linear.** For a byte image, values are written to the PNG
   verbatim in the image's own colourspace. An sRGB→linear conversion on the way in
   double-darkens everything (red `0.10` lands as `#03` instead of `#1A`).
2. **`curve.to_mesh()` already makes a UV layer called `UVMap`.** `uv_layers.new("UVMap")`
   is silently *renamed* to `UVMap.001`; the material keeps reading the original
   full-atlas unwrap and every glyph samples a random palette cell.
3. **`mesh.materials.clear()` resets every polygon's `material_index` to 0.** Clearing
   and re-appending looks fine (2 slots, correct names) but has already collapsed the
   face/return split into one flat material.
4. **Font curves extrude along Z, so a glyph's *height* is its Y extent.** Measuring Z
   on an un-rotated glyph returns the extrusion depth, or 0 if it's flat.

And one aesthetic one: the scene uses the **`Standard`** view transform, not AgX. AgX is
a filmic transform that desaturates values as they approach clipping — it turned the
authored cyan into powder blue and the pink into salmon. Here the palette's exact RGB
*is* the deliverable, so no film curve.
