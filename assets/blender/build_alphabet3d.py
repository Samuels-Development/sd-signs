"""
build_alphabet3d.py  --  3D emissive alphabet generator for Blender (tested on 5.2 LTS)

Builds A-Z, a-z and 0-9 as extruded "channel letter" props (62 meshes) plus a single
4x4 palette texture holding 10 emissive colours.  Colour is a PER-OBJECT integer
property, not per-mesh data, so all 620 char/colour combinations are linked
duplicates of the same 62 meshes:  62 meshes + 2 materials + 1 texture, total.

Run from Blender:  Scripting workspace -> open this file -> Run
Headless:          blender -b -P build_alphabet3d.py

WARNING: main() wipes the current .blend scene.
"""

import bpy, bmesh, math, os, string
from mathutils import Matrix, Euler, Vector

# --------------------------------------------------------------------------
# CONFIG
# --------------------------------------------------------------------------
# The toolchain lives inside the resource, at sd-signs/assets/blender, so it resolves
# its own location rather than hardcoding one machine's paths. runpy.run_path -- which
# is how export_fivem.py and measure_glyphs.py load this file -- sets __file__, so this
# works for them too. Only a bare exec() of the source misses it, hence the fallback.
try:
    OUT_DIR = os.path.dirname(os.path.abspath(__file__))
except NameError:
    OUT_DIR = "C:/txData/Qbox_6CE7D0.base/resources/[standalone]/sd-signs/assets/blender"

# Intermediates: Sollumz staging duplicates every .ydr already in stream/, and the glTF
# export runs to ~54 MB. Neither belongs in git or in a folder the server scans, so both
# are gitignored -- and A3D_BUILD_DIR moves them off the resource tree entirely.
BUILD_DIR = os.environ.get("A3D_BUILD_DIR") or os.path.join(OUT_DIR, "build")

TEX_DIR = os.path.join(OUT_DIR, "textures")
EXP_DIR = os.path.join(BUILD_DIR, "export")

# Montserrat Bold, SIL Open Font License 1.1 -- see fonts/OFL.txt. The OFL permits
# redistributing derived artwork (these meshes), which a system font like Arial does
# not, so the font ships with the toolchain rather than being read out of C:\Windows.
#
# Swapping it is supported but not free: every replacement must cover all 129 glyphs
# (Roboto Bold, for one, has no left/right arrow), and changing the face changes every
# advance width, so build -> gen_glyphs_lua.js -> export_fivem.py must all be re-run.
# It must also be a *static* Bold: Blender loads a variable font's default instance,
# which is Regular, and the letters would silently come out thin.
FONT_PATH = os.path.join(OUT_DIR, "fonts", "Montserrat-Bold.ttf")

CAP_H    = 1.0     # metres. True cap height of 'H' (the bevel adds a small skirt)
DEPTH    = 0.12    # total front-to-back extrusion, metres
BEVEL    = 0.010   # rounded edge radius, metres
RES_U    = 4       # font curve resolution -> ~1300 tris/glyph. Raise for smoother curves.
EMISSION = 1.0     # emission strength on the letter face. Above ~1.5 the tonemapper
                   # starts desaturating the hue toward white.

PITCH_X, PITCH_Z = 1.5, 1.75   # chart layout spacing
TRACKING  = 0.12 * CAP_H       # default gap between letters in spawn_text()
SPACE_ADV = 0.35 * CAP_H       # advance width of a space character

# Palette cells 0-9 are the ten emissive colours; 10/11 are the letter returns (sides).
PALETTE = [
    ("white",  (1.00, 1.00, 1.00)),
    ("red",    (1.00, 0.10, 0.08)),
    ("orange", (1.00, 0.38, 0.05)),
    ("amber",  (1.00, 0.66, 0.08)),
    ("yellow", (1.00, 0.94, 0.15)),
    ("green",  (0.16, 0.95, 0.25)),
    ("cyan",   (0.10, 0.90, 1.00)),
    ("blue",   (0.10, 0.35, 1.00)),
    ("purple", (0.55, 0.20, 1.00)),
    ("pink",   (1.00, 0.15, 0.65)),
]
# Returns are lifted off pure black so the extrusion still reads as 3D against a
# dark background -- at 0.055 the sides disappeared entirely and letters looked flat.
RETURN_DARK  = (0.115, 0.115, 0.130)   # cell 10  (return_style = 0)
RETURN_LIGHT = (0.360, 0.360, 0.375)   # cell 11  (return_style = 1)
RETURN_CELL  = 10

GRID = 4                     # palette is GRID x GRID cells
CELL = 1.0 / GRID            # 0.25 UV units per cell
RES  = 512                   # palette texture resolution in px
CPX  = RES // GRID

# Every glyph's UVs are parked in this square inside cell 0. The material shifts it
# to the target cell. Margins are deliberately huge so mipmaps can never bleed.
UVSQ = [(0.09, 0.09), (0.16, 0.09), (0.16, 0.16), (0.09, 0.16)]

PALNAMES = [p[0] for p in PALETTE]

# Symbols need an ASCII slug: a GTA model name may only contain lowercase letters,
# digits and underscores, so '?' cannot appear in one. Every entry here was verified
# to exist in Montserrat Bold by probing against the font's .notdef signature.
SYMBOLS = {
    '.': 'period',  ',': 'comma',    ':': 'colon',    ';': 'semi',
    '!': 'excl',    '?': 'quest',    "'": 'apos',     '"': 'dquote',
    '(': 'lparen',  ')': 'rparen',   '[': 'lbrack',   ']': 'rbrack',
    '{': 'lbrace',  '}': 'rbrace',   '<': 'lt',       '>': 'gt',
    '+': 'plus',    '-': 'hyphen',   '=': 'eq',       '*': 'star',
    '/': 'slash',   '\\': 'bslash',  '%': 'pct',      '&': 'amp',
    '@': 'at',      '#': 'hash',     '$': 'dollar',   '_': 'uscore',
    '|': 'pipe',    '~': 'tilde',    '^': 'caret',
    '°': 'deg',      '€': 'euro',    '£': 'pound',
    '¥': 'yen',      '¢': 'cent',    '©': 'copy',
    '®': 'reg',      '™': 'tm',      '§': 'sect',
    '•': 'bullet',   '…': 'ellip',   '±': 'plusmin',
    '×': 'times',    '÷': 'divide',  '¼': 'quarter',
    '½': 'half',     '¾': 'threeq',  '«': 'laquo',
    '»': 'raquo',    '¡': 'iexcl',   '¿': 'iquest',
    '→': 'arrr',     '←': 'arrl',    '↑': 'arru',
    '↓': 'arrd',     '≤': 'le',      '≥': 'ge',
    '≠': 'ne',       '∞': 'inf',     '√': 'sqrt',
    '¶': 'para',     '†': 'dagger',  '‡': 'ddagger',
    'µ': 'micro',    'ª': 'ordfa',   'º': 'ordfm',
}

CHARSET = (list(string.ascii_uppercase) + list(string.ascii_lowercase)
           + list(string.digits) + list(SYMBOLS.keys()))


def obj_name(ch):
    """Object names carry a U_/L_/D_/S_ tag because Windows filenames are
    case-insensitive: 'AL_U_A' vs 'AL_L_A' survives a per-glyph file export,
    'A' vs 'a' would not.

    SYMBOLS is checked first on purpose: Python considers 'micro' and the feminine
    ordinal to be lowercase letters, so a letters-first test would misroute them.
    """
    slug = SYMBOLS.get(ch)
    if slug: return "AL_S_" + slug.upper()
    if ch.isupper(): return "AL_U_" + ch
    if ch.islower(): return "AL_L_" + ch.upper()
    if ch.isdigit(): return "AL_D_" + ch
    return None


ORDER = [obj_name(c) for c in CHARSET]


# --------------------------------------------------------------------------
# 1. palette texture
# --------------------------------------------------------------------------
def build_palette():
    os.makedirs(TEX_DIR, exist_ok=True)
    for im in list(bpy.data.images):
        if im.name.startswith("alphabet_palette"):
            bpy.data.images.remove(im)

    img = bpy.data.images.new("alphabet_palette", width=RES, height=RES, alpha=False)
    img.colorspace_settings.name = 'sRGB'
    cells = [c[1] for c in PALETTE] + [RETURN_DARK, RETURN_LIGHT] + [(0, 0, 0)] * 4

    # NOTE: for a byte image, image.pixels values are written to the PNG verbatim in
    # the image's OWN colourspace. Do NOT srgb->linear convert here, or every colour
    # comes out double-darkened (red 0.10 lands as #03 instead of #1A).
    px = [0.0] * (RES * RES * 4)
    for idx, col in enumerate(cells):
        cx, cy = idx % GRID, idx // GRID          # cell row 0 == bottom of the image
        for y in range(cy * CPX, (cy + 1) * CPX):
            base = y * RES * 4
            for x in range(cx * CPX, (cx + 1) * CPX):
                o = base + x * 4
                px[o], px[o + 1], px[o + 2], px[o + 3] = col[0], col[1], col[2], 1.0
    img.pixels.foreach_set(px)
    img.filepath_raw = os.path.join(TEX_DIR, "alphabet_palette.png")
    img.file_format = 'PNG'
    img.save()
    img.pack()
    return img


# --------------------------------------------------------------------------
# 2. materials
# --------------------------------------------------------------------------
def build_materials(img):
    for ng in list(bpy.data.node_groups):
        if ng.name.startswith("AL_"): bpy.data.node_groups.remove(ng)
    for m in list(bpy.data.materials):
        if m.name.startswith("AL_"): bpy.data.materials.remove(m)

    # --- node group: float Index -> Colour of that palette cell -------------
    ng = bpy.data.node_groups.new("AL_PaletteCell", 'ShaderNodeTree')
    ng.interface.new_socket("Index", in_out='INPUT',  socket_type='NodeSocketFloat')
    ng.interface.new_socket("Color", in_out='OUTPUT', socket_type='NodeSocketColor')
    n = ng.nodes
    gin  = n.new('NodeGroupInput');  gin.location  = (-900, 0)
    gout = n.new('NodeGroupOutput'); gout.location = (300, 0)
    uv   = n.new('ShaderNodeUVMap'); uv.uv_map = "UVMap"; uv.location = (-900, -260)
    mod  = n.new('ShaderNodeMath'); mod.operation  = 'MODULO';   mod.location  = (-700, 120)
    div  = n.new('ShaderNodeMath'); div.operation  = 'DIVIDE';   div.location  = (-700, -60)
    flr  = n.new('ShaderNodeMath'); flr.operation  = 'FLOOR';    flr.location  = (-520, -60)
    mulu = n.new('ShaderNodeMath'); mulu.operation = 'MULTIPLY'; mulu.location = (-520, 120)
    mulv = n.new('ShaderNodeMath'); mulv.operation = 'MULTIPLY'; mulv.location = (-340, -60)
    comb = n.new('ShaderNodeCombineXYZ'); comb.location = (-160, 40)
    mp   = n.new('ShaderNodeMapping');    mp.vector_type = 'POINT'; mp.location = (0, -60)
    tex  = n.new('ShaderNodeTexImage');   tex.image = img
    tex.interpolation = 'Closest'; tex.extension = 'EXTEND'; tex.location = (150, -260)

    mod.inputs[1].default_value  = float(GRID)
    div.inputs[1].default_value  = float(GRID)
    mulu.inputs[1].default_value = CELL
    mulv.inputs[1].default_value = CELL
    L = ng.links.new
    L(gin.outputs["Index"], mod.inputs[0]); L(gin.outputs["Index"], div.inputs[0])
    L(mod.outputs[0], mulu.inputs[0]);      L(div.outputs[0], flr.inputs[0])
    L(flr.outputs[0], mulv.inputs[0])
    L(mulu.outputs[0], comb.inputs['X']);   L(mulv.outputs[0], comb.inputs['Y'])
    L(uv.outputs[0], mp.inputs['Vector']);  L(comb.outputs[0], mp.inputs['Location'])
    L(mp.outputs[0], tex.inputs['Vector']); L(tex.outputs['Color'], gout.inputs["Color"])

    def blank(name):
        m = bpy.data.materials.new(name); m.use_nodes = True
        nt = m.node_tree
        for nd in list(nt.nodes):
            if nd.type not in {'OUTPUT_MATERIAL', 'BSDF_PRINCIPLED'}: nt.nodes.remove(nd)
        return m, nt, next(nd for nd in nt.nodes if nd.type == 'BSDF_PRINCIPLED')

    # --- face: emissive, cell = object["color_id"] --------------------------
    mF, ntF, bF = blank("AL_Face_Emissive")
    a = ntF.nodes.new('ShaderNodeAttribute')
    a.attribute_type = 'OBJECT'; a.attribute_name = "color_id"; a.location = (-700, 0)
    g = ntF.nodes.new('ShaderNodeGroup'); g.node_tree = ng; g.location = (-450, 0)
    ntF.links.new(a.outputs['Fac'], g.inputs['Index'])
    ntF.links.new(g.outputs['Color'], bF.inputs['Base Color'])
    ntF.links.new(g.outputs['Color'], bF.inputs['Emission Color'])
    bF.inputs['Emission Strength'].default_value = EMISSION
    bF.inputs['Roughness'].default_value = 0.35

    # --- return: dark metal sides, cell = 10 + object["return_style"] -------
    # the +10 means a missing property (-> 0) still resolves to the dark return.
    mR, ntR, bR = blank("AL_Return_Metal")
    aR = ntR.nodes.new('ShaderNodeAttribute')
    aR.attribute_type = 'OBJECT'; aR.attribute_name = "return_style"; aR.location = (-900, 0)
    add = ntR.nodes.new('ShaderNodeMath'); add.operation = 'ADD'
    add.inputs[1].default_value = float(RETURN_CELL); add.location = (-700, 0)
    gR = ntR.nodes.new('ShaderNodeGroup'); gR.node_tree = ng; gR.location = (-450, 0)
    ntR.links.new(aR.outputs['Fac'], add.inputs[0])
    ntR.links.new(add.outputs[0], gR.inputs['Index'])
    ntR.links.new(gR.outputs['Color'], bR.inputs['Base Color'])
    bR.inputs['Metallic'].default_value  = 0.75
    bR.inputs['Roughness'].default_value = 0.32
    bR.inputs['Emission Strength'].default_value = 0.0

    # --- baked variants used for glTF/FBX export (no attribute maths) -------
    def baked(name, emissive):
        m, nt, b = blank(name)
        u = nt.nodes.new('ShaderNodeUVMap'); u.uv_map = "UVMap"; u.location = (-600, -150)
        t = nt.nodes.new('ShaderNodeTexImage'); t.image = img
        t.interpolation = 'Closest'; t.extension = 'EXTEND'; t.location = (-400, 0)
        nt.links.new(u.outputs[0], t.inputs['Vector'])
        nt.links.new(t.outputs['Color'], b.inputs['Base Color'])
        if emissive:
            nt.links.new(t.outputs['Color'], b.inputs['Emission Color'])
            b.inputs['Emission Strength'].default_value = EMISSION
            b.inputs['Roughness'].default_value = 0.35
        else:
            b.inputs['Emission Strength'].default_value = 0.0
            b.inputs['Metallic'].default_value  = 0.75
            b.inputs['Roughness'].default_value = 0.32
        return m

    baked("AL_Face_Baked", True)
    baked("AL_Return_Baked", False)
    return mF, mR


# --------------------------------------------------------------------------
# 3. glyph geometry
# --------------------------------------------------------------------------
def _cap_height(font):
    """True cap height of 'H' at size 1.0.

    Font curves live in the XY plane and extrude along Z, so the glyph's HEIGHT is
    its Y extent. Measuring Z here would return the extrusion depth (or 0 if flat).
    """
    cu = bpy.data.curves.new("__cal", type='FONT')
    cu.body = "H"; cu.font = font; cu.size = 1.0
    cu.align_x = 'CENTER'; cu.align_y = 'TOP_BASELINE'
    cu.extrude = 0.0; cu.bevel_depth = 0.0
    ob = bpy.data.objects.new("__cal", cu); bpy.context.collection.objects.link(ob)
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    ys = [v.co.y for v in me.vertices]
    h = max(ys) - min(ys)
    bpy.data.objects.remove(ob); bpy.data.curves.remove(cu); bpy.data.meshes.remove(me)
    return h


def build_glyph(char, name, font, scale, matF, matR):
    cu = bpy.data.curves.new(name + "_crv", type='FONT')
    cu.body = char; cu.font = font; cu.size = 1.0
    cu.align_x = 'CENTER'          # origin sits on the baseline, horizontally centred
    cu.align_y = 'TOP_BASELINE'
    cu.extrude = (DEPTH / scale) / 2.0
    cu.bevel_depth = BEVEL / scale
    cu.bevel_resolution = 1
    cu.resolution_u = RES_U

    tmp = bpy.data.objects.new(name + "_tmp", cu)
    bpy.context.collection.objects.link(tmp)
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    me.name = name
    bpy.data.objects.remove(tmp); bpy.data.curves.remove(cu)

    me.transform(Matrix.Scale(scale, 4))                            # cap height -> CAP_H
    me.transform(Matrix.Translation((0, 0, DEPTH / 2.0 + BEVEL)))   # back face -> plane 0
    me.transform(Matrix.Rotation(math.radians(90), 4, 'X'))         # stand up, face -Y

    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(me); bm.free()

    me.materials.append(matF)      # slot 0 = lit face
    me.materials.append(matR)      # slot 1 = returns / back
    for p in me.polygons:
        p.material_index = 0 if p.normal.y < -0.90 else 1   # -Y is the front
        p.use_smooth = False

    # curve->mesh conversion ALREADY made a layer called "UVMap". uv_layers.new()
    # would silently be renamed "UVMap.001" and the material would keep reading the
    # original full-atlas unwrap, sampling random palette cells. Overwrite in place.
    for l in [l for l in me.uv_layers if l.name != "UVMap"]:
        me.uv_layers.remove(l)
    uvl = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
    me.uv_layers.active = uvl
    for p in me.polygons:
        for k, li in enumerate(p.loop_indices):
            uvl.data[li].uv = UVSQ[k % 4]

    ob = bpy.data.objects.new(name, me)
    vs = [v.co for v in me.vertices]
    ob["glyph"] = char
    ob["color_id"] = 0
    ob["return_style"] = 0
    ob["width"] = round(max(v.x for v in vs) - min(v.x for v in vs), 6)
    return ob


def build_glyphs():
    font = bpy.data.fonts.load(FONT_PATH, check_existing=True)
    scale = CAP_H / _cap_height(font)
    matF = bpy.data.materials["AL_Face_Emissive"]
    matR = bpy.data.materials["AL_Return_Metal"]
    root = bpy.data.collections.new("Alphabet3D")
    bpy.context.scene.collection.children.link(root)
    master = bpy.data.collections.new("AL_Master"); root.children.link(master)

    for ch in CHARSET:
        master.objects.link(build_glyph(ch, obj_name(ch), font, scale, matF, matR))
    return root, master


def layout_master(per_row=13):
    rows = [ORDER[i:i + per_row] for i in range(0, len(ORDER), per_row)]
    lay = {}
    for r, row in enumerate(rows):
        x0 = -(len(row) - 1) * PITCH_X / 2.0
        for i, nm in enumerate(row):
            lay[nm] = (x0 + i * PITCH_X, 0.0, (len(rows) - 1 - r) * PITCH_Z)
            bpy.data.objects[nm].location = lay[nm]
    return lay


# --------------------------------------------------------------------------
# 4. the point of the whole thing: cheap variants
# --------------------------------------------------------------------------
def colour_index(colour):
    return colour if isinstance(colour, int) else PALNAMES.index(colour)


def set_colour(ob, colour, return_style=None):
    """Recolour an object. O(1), allocates no mesh, works on linked duplicates."""
    ob["color_id"] = colour_index(colour)
    if return_style is not None:
        ob["return_style"] = int(return_style)
    ob.update_tag()
    return ob


def spawn(char, colour="white", location=(0, 0, 0), collection=None):
    """One glyph, linked to the master mesh (adds no mesh data to the file)."""
    src = bpy.data.objects[obj_name(char)]
    ob = bpy.data.objects.new(f"{obj_name(char)}__{PALNAMES[colour_index(colour)]}", src.data)
    ob.location = location
    ob["glyph"] = char; ob["width"] = src["width"]; ob["return_style"] = 0
    set_colour(ob, colour)
    (collection or bpy.context.scene.collection).objects.link(ob)
    return ob


def spawn_text(text, colour="white", location=(0, 0, 0), tracking=None,
               collection=None, per_char_colours=None):
    """Build a sign out of individual channel letters, centred on `location`.

    Letters are spaced optically (bbox width + tracking), which is how real
    channel-letter signage is set, rather than by font kerning pairs.
    `per_char_colours` optionally overrides the colour of each character, e.g.
        spawn_text("QBOX", per_char_colours=["red","amber","green","cyan"])
    """
    tracking = TRACKING if tracking is None else tracking
    advances = [SPACE_ADV if ch == " " else bpy.data.objects[obj_name(ch)]["width"]
                for ch in text]
    total = sum(advances) + tracking * (len(text) - 1)

    coll = collection or bpy.context.scene.collection
    out, x = [], -total / 2.0
    for i, ch in enumerate(text):
        if ch != " ":
            col = per_char_colours[i] if per_char_colours else colour
            out.append(spawn(ch, col, (location[0] + x + advances[i] / 2.0,
                                       location[1], location[2]), coll))
        x += advances[i] + tracking
    return out


# --------------------------------------------------------------------------
# 5. export (bakes the palette offset into real UVs)
# --------------------------------------------------------------------------
def cell_uv(idx):
    return ((idx % GRID) * CELL, (idx // GRID) * CELL)


def bake_mesh(src_me, colour):
    """Copy a master mesh with the palette offset written into its UVs.

    Exported formats cannot carry Blender object-attributes, so the colour has to
    stop being a per-object property and become real UV data at export time.
    """
    cid = colour_index(colour)
    me = src_me.copy(); me.name = src_me.name + "_bake"

    # Swap the materials IN PLACE. materials.clear() would also silently reset every
    # polygon's material_index to 0, collapsing the face/return split -- the export
    # would still look plausible (2 slots, right names) but ship one flat material.
    me.materials[0] = bpy.data.materials["AL_Face_Baked"]
    me.materials[1] = bpy.data.materials["AL_Return_Baked"]

    uvl = me.uv_layers["UVMap"]
    fu, fv = cell_uv(cid); ru, rv = cell_uv(RETURN_CELL)
    for p in me.polygons:
        du, dv = (fu, fv) if p.material_index == 0 else (ru, rv)
        for li in p.loop_indices:
            u, v = uvl.data[li].uv
            uvl.data[li].uv = (u + du, v + dv)
    return me


def export_colour_set(colour, layout):
    """All 62 glyphs in one colour -> a single .glb, laid out as a readable chart."""
    os.makedirs(EXP_DIR, exist_ok=True)
    name = PALNAMES[colour_index(colour)]
    tmp = bpy.data.collections.new("__bake_" + name)
    bpy.context.scene.collection.children.link(tmp)
    objs = []
    for nm in ORDER:
        ob = bpy.data.objects.new(nm.replace("AL_", ""),
                                  bake_mesh(bpy.data.objects[nm].data, colour))
        ob.location = layout[nm]
        tmp.objects.link(ob); objs.append(ob)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    fp = os.path.join(EXP_DIR, f"alphabet_{name}.glb")
    bpy.ops.export_scene.gltf(filepath=fp, export_format='GLB', use_selection=True)
    for o in objs:
        m = o.data; bpy.data.objects.remove(o); bpy.data.meshes.remove(m)
    bpy.data.collections.remove(tmp)
    return fp


def export_single(char, colour, filepath):
    """One glyph in one colour, at the origin -- for engines wanting one asset per file."""
    tmp = bpy.data.collections.new("__bake_one")
    bpy.context.scene.collection.children.link(tmp)
    ob = bpy.data.objects.new(obj_name(char).replace("AL_", ""),
                              bake_mesh(bpy.data.objects[obj_name(char)].data, colour))
    tmp.objects.link(ob)
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True); bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=filepath, export_format='GLB', use_selection=True)
    m = ob.data; bpy.data.objects.remove(ob); bpy.data.meshes.remove(m)
    bpy.data.collections.remove(tmp)
    return filepath


# --------------------------------------------------------------------------
# 6. scene dressing + showcase
# --------------------------------------------------------------------------
def build_showcase(root):
    """Every glyph x every colour: 620 objects sharing the same 62 meshes."""
    show = bpy.data.collections.new("AL_Showcase"); root.children.link(show)
    sx, sz = -105.0, -4.0
    for ci, cname in enumerate(PALNAMES):
        for gi, nm in enumerate(ORDER):
            src = bpy.data.objects[nm]
            ob = bpy.data.objects.new(f"{nm}__{cname}", src.data)   # linked duplicate
            ob.location = (sx + gi * PITCH_X, 0.0, sz - ci * PITCH_Z)
            ob["glyph"] = src["glyph"]; ob["width"] = src["width"]
            ob["color_id"] = ci; ob["return_style"] = 0
            show.objects.link(ob)
    return show


def setup_scene(backdrop=True):
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE'
    w = bpy.data.worlds.new("AL_World"); w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.012, 0.012, 0.016, 1)
    sc.world = w

    # 'Standard', NOT AgX. AgX is a filmic transform that desaturates values as they
    # approach clipping -- it turns the authored cyan into powder blue and pink into
    # salmon. Here the palette's exact RGB *is* the deliverable, so no film curve.
    sc.view_settings.view_transform = 'Standard'
    sc.render.resolution_x, sc.render.resolution_y = 1600, 900
    sc.eevee.taa_render_samples = 96

    if backdrop:
        # letters occupy Y = -DEPTH-2*BEVEL .. 0, so a wall at Y=0 sits flush behind
        # them; the contact shadow it catches is what makes the extrusion read.
        me = bpy.data.meshes.new("AL_BackdropMesh")
        me.from_pydata([(-200, 0, -200), (200, 0, -200), (200, 0, 200), (-200, 0, 200)],
                       [], [(0, 1, 2, 3)])
        me.update()
        bd = bpy.data.objects.new("AL_Backdrop", me)
        bd.location = (0, 0.02, 0)
        mb = bpy.data.materials.new("AL_BackdropMat"); mb.use_nodes = True
        bb = mb.node_tree.nodes["Principled BSDF"]
        bb.inputs['Base Color'].default_value = (0.021, 0.021, 0.026, 1)
        bb.inputs['Roughness'].default_value = 0.55
        me.materials.append(mb)
        sc.collection.objects.link(bd)

    lt = bpy.data.lights.new("AL_KeyData", 'AREA'); lt.energy = 2000; lt.size = 20
    key = bpy.data.objects.new("AL_Key", lt)
    key.location = (-8, -14, 12)
    key.rotation_euler = Euler((math.radians(48), 0, math.radians(-32)))
    sc.collection.objects.link(key)

    cd = bpy.data.cameras.new("AL_CamData"); cd.lens = 50
    cam = bpy.data.objects.new("AL_Cam", cd)
    cam.location = (0, -26, 3.5); cam.rotation_euler = Euler((math.radians(90), 0, 0))
    sc.collection.objects.link(cam); sc.camera = cam


def build_demo(root):
    """A small sign demonstrating mixed per-letter colours on shared meshes."""
    demo = bpy.data.collections.new("AL_Demo"); root.children.link(demo)
    spawn_text("Qbox", location=(30, 0, 6.0), collection=demo,
               per_char_colours=["cyan", "pink", "amber", "green"])
    spawn_text("alphabet 3d", colour="orange", location=(30, 0, 3.4), collection=demo)
    spawn_text("0123456789", colour="blue", location=(30, 0, 0.9), collection=demo)
    return demo


def render_previews():
    """Three framed stills: the demo sign, the character chart, the full colour grid."""
    sc = bpy.context.scene
    cam = bpy.data.objects["AL_Cam"]
    cd = bpy.data.cameras["AL_CamData"]
    key = bpy.data.objects["AL_Key"]

    def aim(c, t):
        c.rotation_euler = (Vector(t) - c.location).to_track_quat('-Z', 'Y').to_euler()

    def shot(name, loc, target, lens, keyloc, energy, res, ortho=None):
        # reference sheets use an orthographic camera: no perspective fall-off across
        # a 93 m wide grid, and ortho_scale frames it exactly instead of by trial.
        cd.type = 'ORTHO' if ortho else 'PERSP'
        if ortho: cd.ortho_scale = ortho
        else:     cd.lens = lens
        cam.location = loc; aim(cam, target)
        key.location = keyloc
        bpy.data.lights["AL_KeyData"].energy = energy
        sc.render.resolution_x, sc.render.resolution_y = res
        sc.render.filepath = os.path.join(OUT_DIR, name)
        sc.render.image_settings.file_format = 'PNG'
        bpy.ops.render.render(write_still=True)
        return os.path.join(OUT_DIR, name + ".png")

    # Frame the charts from the actual layout rather than hardcoded numbers, so
    # adding glyphs (symbols, say) cannot silently push rows out of shot.
    per_row = 13
    rows = math.ceil(len(ORDER) / per_row)
    chart_w = per_row * PITCH_X + 2.0
    chart_h = rows * PITCH_Z + 1.5
    chart_cz = (rows - 1) * PITCH_Z / 2.0
    chart_res = (1500, 1500)
    chart_ortho = max(chart_w, chart_h * (chart_res[0] / chart_res[1]))

    grid_w = len(ORDER) * PITCH_X + 3.0
    grid_cx = -105.0 + (len(ORDER) - 1) * PITCH_X / 2.0
    grid_cz = -4.0 - (len(PALNAMES) - 1) * PITCH_Z / 2.0
    grid_res = (3400, 760)
    grid_ortho = max(grid_w, (len(PALNAMES) * PITCH_Z + 2.0) * (grid_res[0] / grid_res[1]))

    out = [
        # hero: perspective 3/4 so the extrusion and returns are visible
        shot("preview_hero",  (26.0, -8.0, 8.0), (30.2, 0.0, 6.35), 55, (26, -9, 13), 4000, (1600, 900)),
        # character chart: every glyph, orthographic
        shot("preview_chart", (0.0, -60.0, chart_cz), (0.0, 0.0, chart_cz), 0, (-8, -14, 16), 4000,
             chart_res, ortho=chart_ortho),
        # the full glyph x colour grid, orthographic, wide aspect to suit the block
        shot("preview_grid",  (grid_cx, -200.0, grid_cz), (grid_cx, 0.0, grid_cz), 0,
             (grid_cx, -60, 6), 20000, grid_res, ortho=grid_ortho),
        # near-edge-on, showing the 0.140 m thickness and the dark returns
        shot("preview_edge",  (37.5, -2.2, 6.6), (29.5, -0.07, 6.35), 55, (34, -8, 11), 4000, (1600, 900)),
    ]

    # rear view: proves the letters are closed solids with a real back face.
    # The backdrop wall sits behind them so it has to go, and the returns are switched
    # to the light variant because the default near-black ones read as nothing.
    bd = bpy.data.objects.get("AL_Backdrop")
    qbox = [o for o in bpy.data.collections["AL_Demo"].objects
            if abs(o.location.z - 6.0) < 0.01] if "AL_Demo" in bpy.data.collections else []
    for o in qbox:
        o["return_style"] = 1
        o.update_tag()          # EEVEE caches per-object attributes; this forces a refresh
    fd = bpy.data.lights.new("AL_FillData", 'AREA'); fd.size = 8; fd.energy = 3000
    fill = bpy.data.objects.new("AL_Fill", fd); sc.collection.objects.link(fill)
    fill.location = (26.0, 6.0, 7.5); aim(fill, (30.2, 0.0, 6.35))
    if bd: bd.hide_render = True
    bpy.context.view_layer.update()

    out.append(shot("preview_back", (33.8, 7.0, 8.0), (30.2, 0.0, 6.35), 55, (33, 6, 12),
                    12000, (1600, 900)))

    if bd: bd.hide_render = False
    for o in qbox:
        o["return_style"] = 0
        o.update_tag()
    bpy.data.objects.remove(fill); bpy.data.lights.remove(fd)
    cd.type = 'PERSP'; cd.lens = 50
    return out


def wipe():
    for ob in list(bpy.data.objects): bpy.data.objects.remove(ob)
    for c in list(bpy.data.collections): bpy.data.collections.remove(c)
    for db in (bpy.data.meshes, bpy.data.materials, bpy.data.images,
               bpy.data.curves, bpy.data.node_groups, bpy.data.lights, bpy.data.cameras):
        for blk in list(db):
            try: db.remove(blk)
            except Exception: pass


def main(showcase=True, demo=True, previews=True, do_export=True, save=True):
    wipe()
    img = build_palette()
    build_materials(img)
    root, master = build_glyphs()
    layout = layout_master()
    if showcase:
        build_showcase(root)
    setup_scene()
    if demo:
        build_demo(root)
    if previews:
        render_previews()
    if do_export:
        import logging
        logging.disable(logging.INFO)
        for name in PALNAMES:
            export_colour_set(name, layout)
        logging.disable(logging.NOTSET)
    if save:
        os.makedirs(OUT_DIR, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "alphabet3d.blend"))
    print(f"done: {len(master.objects)} glyphs, {len(bpy.data.meshes)} meshes, "
          f"{len(bpy.data.materials)} materials, {len(bpy.data.images)} texture")


if __name__ == "__main__":
    main()
