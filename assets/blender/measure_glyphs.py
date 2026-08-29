"""
measure_glyphs.py  --  writes glyph_metrics.json from the built glyph meshes.

Step 2 of 3 in the pipeline:

    build_alphabet3d.py   meshes + palette      (run first, in Blender)
    measure_glyphs.py     glyph_metrics.json    (this file, in Blender)
    gen_glyphs_lua.js     shared/glyphs.lua     (node, outside Blender)
    export_fivem.py       stream/*.ydr + .ytyp  (in Blender)

Sign layout in game has to agree with the props down to the millimetre, so the
advance widths are *measured off the real meshes* rather than read from the font.
The mesh is what ships, and it differs from the font's own advance: the bevel adds
BEVEL to every side, and round glyphs overshoot the cap line.

Everything is expressed in cap-height units (cap == 1.0), so a sign scales by simply
multiplying, and none of these numbers change when the sign size slider moves.

Run from Blender AFTER build_alphabet3d.py has populated the scene:
    exec(open(r"...\\measure_glyphs.py").read())
"""

import bpy, json, os, runpy

# Resolves itself; see the note on OUT_DIR in build_alphabet3d.py.
try:
    OUT = os.path.dirname(os.path.abspath(__file__))
except NameError:
    OUT = "C:/txData/Qbox_6CE7D0.base/resources/[standalone]/sd-signs/assets/blender"

# run_path rather than import: the toolchain is a folder of scripts, not a package,
# and Blender's sys.path does not include it. __name__ is not "__main__" under
# run_path, so build_alphabet3d's own main() does not fire and wipe the scene.
AL = runpy.run_path(os.path.join(OUT, "build_alphabet3d.py"))

DST = os.path.join(OUT, "glyph_metrics.json")


def base_model(char):
    """sd_a3d_<tag><char-or-slug>, i.e. model_name() in export_fivem.py without the
    colour suffix. Kept in step with that function by hand; they are two lines each
    and lived in one place would mean importing the exporter just to measure.

    SYMBOLS is checked first for the same reason it is there: Python classes the
    micro sign and the feminine ordinal as lowercase letters, so a letters-first
    test would misroute them into the 'l' namespace and collide with real letters.

    ACCENTS is checked next, and unlike SYMBOLS it keeps the u/l tag: the slug is
    case-free, so 'Ä' -> sd_a3d_uadiaer and 'ä' -> sd_a3d_ladiaer. Without it the raw
    fallback below would emit 'sd_a3d_lä', and a GTA model name is [a-z0-9_] only.
    """
    slug = AL["SYMBOLS"].get(char)
    if slug:
        return "sd_a3d_s%s" % slug
    tag = "u" if char.isupper() else ("l" if char.islower() else "d")
    accent = AL["ACCENTS"].get(char)
    if accent:
        return "sd_a3d_%s%s" % (tag, accent)
    return "sd_a3d_%s%s" % (tag, char.lower())


def measure(char):
    """Advance width and vertical extent of one glyph, in cap-height units.

    The meshes are built with the origin on the baseline and centred horizontally,
    so the Z bounds are already relative to the baseline and need no correction.
    Returns None for a glyph the build did not produce, so a partial build reports
    what is missing instead of writing a metrics file with a silent hole in it.
    """
    me = bpy.data.meshes.get(AL["obj_name"](char))
    if me is None or not me.vertices:
        return None
    xs = [v.co.x for v in me.vertices]
    zs = [v.co.z for v in me.vertices]
    cap = AL["CAP_H"]
    return {
        "ch": char,
        "model": base_model(char),
        "w": round((max(xs) - min(xs)) / cap, 4),
        "top": round(max(zs) / cap, 4),
        "bot": round(min(zs) / cap, 4),
    }


def main():
    glyphs, missing = [], []
    for ch in AL["CHARSET"]:
        m = measure(ch)
        if m is None:
            missing.append(ch)
        else:
            glyphs.append(m)

    if missing:
        # Loud, because the failure is otherwise invisible: gen_glyphs_lua.js would
        # cheerfully emit a table without these keys and the characters would just
        # vanish from signs at runtime.
        raise RuntimeError("no mesh for %d glyph(s): %s -- run build_alphabet3d.py first"
                           % (len(missing), " ".join(missing)))

    cap = AL["CAP_H"]
    data = {
        "cap": cap,
        "depth": AL["DEPTH"],
        "bevel": AL["BEVEL"],
        "tracking": round(AL["TRACKING"] / cap, 4),
        "space": round(AL["SPACE_ADV"] / cap, 4),
        "palette": AL["PALNAMES"],
        "glyphs": glyphs,
    }
    with open(DST, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=1)

    widths = sorted(glyphs, key=lambda g: g["w"])
    print("wrote %s (%d glyphs)" % (DST, len(glyphs)))
    print("  narrowest %s %.4f   widest %s %.4f"
          % (widths[0]["ch"], widths[0]["w"], widths[-1]["ch"], widths[-1]["w"]))


main()
