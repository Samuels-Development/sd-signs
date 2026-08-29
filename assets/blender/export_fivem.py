"""
export_fivem.py -- batch-export the alphabet as FiveM .ydr props + a .ytyp archetype file.

Run from inside Blender (the Blender MCP or the Scripting tab):

    import runpy
    E = runpy.run_path(r"...\export_fivem.py")
    E["export_style"]("painted")     # 129 .ydr, every colour, one finish
    E["write_ytyp"]()                # one .ytyp covering everything exported so far

Model naming is  sd_a3d_<tag><char>[_neon]  (tag: u/l/d), matching Glyphs.model()
in sd-signs/shared/glyphs.lua. The u/l/d tag exists because Windows filenames are
case-insensitive, so 'A' and 'a' would collide as files.

Colour is NOT in the name and NOT in the geometry. Both finishes use a '_tnt' shader
carrying a tint palette, and the game selects a row per entity via
SET_OBJECT_TEXTURE_VARIATION -- so 129 glyphs x 2 finishes covers the whole palette in
258 models rather than 2580, and an animated sign costs one entity per letter instead
of one per letter per colour.
"""

import bpy
import bmesh
import os
import runpy
import string
import struct

# Resolved from this file's own location, matching build_alphabet3d.py, so a clone runs
# without editing paths. This script sits at sd-signs/assets/blender, which puts the
# resource root two levels up and stream/ inside it. Only a bare exec() of the source
# misses __file__, hence the fallback.
try:
    OUT = os.path.dirname(os.path.abspath(__file__))
except NameError:
    OUT = "C:/txData/Qbox_6CE7D0.base/resources/[standalone]/sd-signs/assets/blender"

# The .ydr are staged outside the resource tree by default: the server scans stream/, and
# a folder of half-exported drawables sitting next to the real ones is asking for trouble.
YDR = os.path.join(os.environ.get("A3D_BUILD_DIR") or os.path.join(OUT, "build"), "fivem")
STREAM = os.path.abspath(os.path.join(OUT, "..", "..", "stream"))
YTYP_NAME = "sd_a3d"

AL = runpy.run_path(os.path.join(OUT, "build_alphabet3d.py"))

DDS_PATH = os.path.join(OUT, "textures", "alphabet_palette.dds")
TINT_PATH = os.path.join(OUT, "textures", "alphabet_tint.dds")


def palette_dds():
    """The DDS build of the palette, loaded and packed.

    Sollumz will only embed a texture whose packed data is actually DDS -- a packed
    PNG is refused at export with a warning and the model ships untextured. The
    Blender-side material points at the PNG (that is what the render previews use),
    so the export path has to swap in the DDS explicitly.
    """
    for im in bpy.data.images:
        if im.filepath and im.filepath.lower().endswith("alphabet_palette.dds"):
            if not im.packed_file:
                im.pack()
            return im
    img = bpy.data.images.load(DDS_PATH, check_existing=True)
    img.colorspace_settings.name = 'sRGB'
    img.pack()
    return img


def write_tint_dds(path=TINT_PATH):
    """The tint palette: one uniform row per palette colour, uncompressed.

    Uncompressed is not a preference, it is required. A DXT1 block is 4x4 pixels, so
    it spans four ROWS -- and a row here is a whole tint index. Compressing this would
    blend indices 0-3 into one another and hand you four muddy colours instead of four
    clean ones. At 16x16x4 bytes the file is 1 KB, so there is nothing to gain anyway.

    Rows are filled edge to edge because the shader picks the COLUMN from the vertex
    colour's red channel. Making every column identical means the glyph meshes need no
    particular Color 0 authoring for the lookup to land on the right colour.
    """
    w = h = 16
    flags = 0x1 | 0x2 | 0x4 | 0x8 | 0x1000        # CAPS HEIGHT WIDTH PITCH PIXELFORMAT
    hdr = b"DDS " + struct.pack("<7I", 124, flags, h, w, w * 4, 0, 0)
    hdr += b"\x00" * 44                            # dwReserved1[11]
    hdr += struct.pack("<8I", 32, 0x41, 0, 32,     # pf: size, RGB|ALPHAPIXELS, fourCC, bpp
                       0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000)
    hdr += struct.pack("<5I", 0x1000, 0, 0, 0, 0)  # caps
    rows = [p[1] for p in AL["PALETTE"]]
    body = bytearray()
    for y in range(h):
        r, g, b = rows[y] if y < len(rows) else (1.0, 1.0, 1.0)
        body += bytes((int(b * 255), int(g * 255), int(r * 255), 255)) * w
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(hdr + bytes(body))
    return path


def tint_dds():
    """The tint palette, rebuilt from PALETTE and packed, so adding a colour to the
    build script is enough -- no geometry and no re-export of the other colours.

    The datablock is REUSED, never replaced. Both finishes' materials point at this
    one image, and bpy.data.images.remove() nulls every reference to it rather than
    just the caller's -- which ships a face with no palette. A _tnt shader with no
    palette renders BLACK, silently, and only in whichever finish was built first.
    Refresh it in place instead: unpack to the file just written, reload, repack.
    """
    write_tint_dds()
    for im in bpy.data.images:
        if im.filepath and im.filepath.lower().endswith("alphabet_tint.dds"):
            if im.packed_file:
                im.unpack(method='USE_ORIGINAL')
            im.reload()
            im.pack()
            return im
    img = bpy.data.images.load(TINT_PATH, check_existing=True)
    img.colorspace_settings.name = 'sRGB'
    img.pack()
    return img


def _scratch():
    coll = bpy.data.collections.get("AL_FiveM")
    if coll is None:
        coll = bpy.data.collections.new("AL_FiveM")
        bpy.context.scene.collection.children.link(coll)
    return coll


#: Shader indices in Sollumz's 296-entry table. Both are '_tnt' shaders: they carry a
#: TintPaletteSampler whose ROW is chosen per entity at runtime by the game's
#: SET_OBJECT_TEXTURE_VARIATION. That is what lets one .ydr serve every colour, and it
#: is why there is no colour in a model name any more.
DEFAULT_TNT_INDEX = 48        # default_tnt.sps  -- the matte "painted" finish
EMISSIVE_TNT_INDEX = 124      # emissive_tnt.sps -- lit face, keeps emissiveMultiplier

#: How hard the neon variant glows. 1.0 is the shader default.
EMISSIVE_MULTIPLIER = 1.6

#: Archetype LOD distance, metres. This is a hard ceiling on visibility that the
#: resource cannot raise: past it the game stops DRAWING a letter even though the
#: entity still exists, so a sign set to render at 2 km would spawn and stay invisible.
#: Keep it at or above sd-signs' Config.MaxRenderDistance.
#:
#: Costs nothing by itself. Whether a letter exists at all is decided per sign by
#: Config.RenderDistance, so a sign set to 120 m is still deleted at 120 m; this only
#: stops the engine from culling the ones deliberately set to carry further.
LOD_DIST = 3200.0


def model_name(char, style="painted"):
    """sd_a3d_<tag><char-or-slug>[_neon].

    Symbols resolve through SYMBOLS first: a GTA model name cannot contain '?' or
    '%', and Python also classes the micro sign and feminine ordinal as lowercase
    letters, so a letters-first test would misroute them into the 'l' namespace.

    Colour used to be the last segment. It is now a runtime tint index, so a glyph is
    one model per finish rather than one per finish per colour: 258 instead of 2580.
    """
    slug = AL["SYMBOLS"].get(char)
    if slug:
        base = "sd_a3d_s%s" % slug
    else:
        tag = "u" if char.isupper() else ("l" if char.islower() else "d")
        base = "sd_a3d_%s%s" % (tag, char.lower())
    return base + ("_neon" if style == "neon" else "")


def face_material(style):
    """The tint-capable face material for one finish, built once and shared.

    Two samplers matter here and they are NOT interchangeable:

      DiffuseSampler     the ordinary palette, whose white cell the face UVs sit on.
                         The shader multiplies diffuse by the tint colour, so the face
                         has to sample white or every colour comes out darkened.
      TintPaletteSampler the 16-row tint palette. The game picks the row per entity.

    Only the FACE gets this. The returns keep their plain default.sps material sampling
    their own dark cell, which is what preserves the lit-face / dark-metal look without
    spending a tint row on it.
    """
    def wire(mat):
        """Point the two samplers at the right images and mark them embedded.

        Run on every call, cache hit included. A cached material is not proof its
        textures are still attached -- anything that frees an image datablock leaves
        the node pointing at None, and re-wiring is idempotent and nearly free.
        """
        diffuse, tint = palette_dds(), tint_dds()
        for node in mat.node_tree.nodes:
            if node.type == 'TEX_IMAGE':
                node.image = tint if node.name == "TintPaletteSampler" else diffuse
                node.texture_properties.embedded = True
            elif node.type == 'CUSTOM' and getattr(node, "name", "") == "emissiveMultiplier":
                # Sollumz parameter nodes carry no input sockets; the value lives on
                # the node itself via as_float/set_float. Writing to node.inputs is a
                # no-op that fails silently and leaves the shader default of 1.0.
                node.as_float = EMISSIVE_MULTIPLIER
        missing = [n.name for n in mat.node_tree.nodes
                   if n.type == 'TEX_IMAGE' and n.image is None]
        if missing:
            raise RuntimeError("%s: samplers left unassigned: %s -- these export as a "
                               "black face" % (mat.name, missing))
        return mat

    name = "AL_Face_Tnt_" + style
    existing = bpy.data.materials.get(name)
    if existing:
        return wire(existing)

    probe = bpy.data.objects.new("__shaderprobe", bpy.data.meshes.new("__shaderprobe"))
    bpy.context.scene.collection.objects.link(probe)
    # A tint shader needs real geometry at creation time: Sollumz runs
    # create_tinted_shader_graph(), which adds a CORNER colour attribute, and an empty
    # mesh has no corners to add it to -- the operator fails with a bare KeyError.
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=1.0)
    bm.to_mesh(probe.data)
    bm.free()
    bpy.ops.object.select_all(action='DESELECT')
    probe.select_set(True)
    bpy.context.view_layer.objects.active = probe
    before = set(bpy.data.materials.keys())
    bpy.ops.sollumz.createshadermaterial(
        shader_index=EMISSIVE_TNT_INDEX if style == "neon" else DEFAULT_TNT_INDEX)
    created = [n for n in bpy.data.materials.keys() if n not in before]
    mesh = probe.data
    bpy.data.objects.remove(probe)
    bpy.data.meshes.remove(mesh)

    mat = bpy.data.materials[created[0]]
    mat.name = name
    return wire(mat)


def build_drawable(char, coll, style="painted"):
    """Blender mesh -> a Sollumz drawable ready for export, with all four
    silent-failure gotchas handled (see the README's Gotchas section)."""
    name = model_name(char, style)
    src = bpy.data.meshes[AL["obj_name"](char)]
    # Always bake against white. The face's colour now arrives at runtime as a tint,
    # and the shader multiplies by the diffuse, so any other cell would tint a tinted
    # colour and come out wrong. The returns' UVs are unaffected by this argument.
    me = AL["bake_mesh"](src, "white")
    me.name = name

    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()

    # 1. Sollumz binds the shader's UVMap node by NAME; it must be "UVMap 0".
    for layer in [l for l in me.uv_layers if l.name != "UVMap 0"]:
        if len(me.uv_layers) > 1:
            me.uv_layers.remove(layer)
    me.uv_layers[0].name = "UVMap 0"

    # 2. default.sps multiplies by a vertex colour channel: without a CORNER-domain
    #    BYTE_COLOR named "Color 1" the model can render black in game. The _tnt
    #    shaders read "Color 0" instead -- only the three trees_*_tnt shaders use
    #    Color 1 -- so both have to exist or the face renders black.
    for attr in ("Color 0", "Color 1"):
        if attr not in me.color_attributes:
            me.color_attributes.new(name=attr, type='BYTE_COLOR', domain='CORNER')
        for d in me.color_attributes[attr].data:
            d.color = (1.0, 1.0, 1.0, 1.0)

    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.sollumz.autoconvertmaterials()
    # 3. The drawable OBJECT's name becomes both the .ydr filename and the model name.
    bpy.ops.sollumz.converttodrawable()

    dds = palette_dds()
    mdl = bpy.data.objects[name + ".model"]
    for mat in mdl.data.materials:
        for node in mat.node_tree.nodes:
            if node.type == 'TEX_IMAGE':
                node.image = dds          # must be the DDS, not the preview PNG
                node.texture_properties.embedded = True

    # Swap only the FACE slot to the tint shader; the returns stay matte metal, which
    # is what makes a real neon letter read as lit tube against a dark can. Assigning
    # in place preserves every polygon's material_index.
    mdl.data.materials[0] = face_material(style)

    return bpy.data.objects[name], mdl


def export_style(style="painted", chars=None, chunk=16):
    """Export every glyph in one finish. Returns the list of model names.

    There is no colour loop any more: one pass per finish covers the whole palette,
    because colour is applied per entity in game rather than baked per model.
    """
    os.makedirs(YDR, exist_ok=True)
    coll = _scratch()
    # Take the charset from the build script so the two can never drift apart.
    chars = chars or list(AL["CHARSET"])
    made = []
    for i in range(0, len(chars), chunk):
        batch = chars[i:i + chunk]
        pairs = [build_drawable(c, coll, style) for c in batch]
        bpy.ops.object.select_all(action='DESELECT')
        for drw, mdl in pairs:
            drw.select_set(True)
            mdl.select_set(True)
        bpy.context.view_layer.objects.active = pairs[0][0]
        # 4. Omitting target_versions writes gen8/ and gen9/ subfolders, not a .ydr.
        bpy.ops.sollumz.export_assets(
            directory=YDR, target_formats={'NATIVE'}, target_versions={'GEN8'},
            limit_to_selected=True, apply_transforms=True, direct_export=True,
            use_custom_settings=True)
        made += [d.name for d, _ in pairs]
    return made


def _ytyp_ctx():
    """Sollumz's ytyp operators poke context.space_data, which MCP execution lacks."""
    area = next(a for a in bpy.context.screen.areas if a.type == 'VIEW_3D')
    region = next(r for r in area.regions if r.type == 'WINDOW')
    return dict(area=area, space_data=area.spaces.active, region=region)


def add_archetypes(names=None, reset=False):
    """Append archetypes for the named drawables to the working ytyp.

    Appending (rather than rebuilding from every drawable in the scene) lets the
    painted set's objects be purged before the neon set is built, which keeps the
    scene small -- archetype creation slows down noticeably as object count grows.
    """
    sc = bpy.context.scene
    coll = _scratch()
    names = names or [o.name for o in coll.objects
                      if getattr(o, 'sollum_type', '') == 'sollumz_drawable']
    with bpy.context.temp_override(**_ytyp_ctx()):
        if reset:
            while len(sc.ytyps):
                bpy.ops.sollumz.deleteytyp()
        if not len(sc.ytyps):
            bpy.ops.sollumz.createytyp()
            sc.ytyps[sc.ytyp_index].name = YTYP_NAME
        yt = sc.ytyps[sc.ytyp_index]
        bpy.ops.object.select_all(action='DESELECT')
        prev = None
        for name in names:
            d = bpy.data.objects[name]
            if prev: prev.select_set(False)
            d.select_set(True)
            bpy.context.view_layer.objects.active = d
            bpy.ops.sollumz.createarchetypefromselected()
            prev = d
        for a in yt.archetypes:
            a.texture_dictionary = ""
            a.lod_dist = LOD_DIST
    return len(yt.archetypes)


def save_ytyp():
    """Write the working ytyp out as a binary .ytyp."""
    with bpy.context.temp_override(**_ytyp_ctx()):
        bpy.ops.sollumz.export_ytyp_io(directory=YDR, target_formats={'NATIVE'},
                                       target_versions={'GEN8'}, use_custom_settings=True)
    return os.path.join(YDR, YTYP_NAME + ".ytyp")


def write_ytyp(names=None):
    """One .ytyp holding an archetype per exported model. Without this the .ydr
    streams fine but CreateObject cannot resolve the model name."""
    sc = bpy.context.scene
    coll = _scratch()
    names = names or [o.name for o in coll.objects
                      if getattr(o, 'sollum_type', '') == 'sollumz_drawable']

    area = next(a for a in bpy.context.screen.areas if a.type == 'VIEW_3D')
    region = next(r for r in area.regions if r.type == 'WINDOW')
    with bpy.context.temp_override(area=area, space_data=area.spaces.active, region=region):
        while len(sc.ytyps):
            bpy.ops.sollumz.deleteytyp()
        bpy.ops.sollumz.createytyp()
        yt = sc.ytyps[sc.ytyp_index]
        yt.name = YTYP_NAME
        # Deselect only the previous object rather than calling select_all(DESELECT):
        # that walks every object in the scene, and with ~2600 objects and 1290
        # archetypes to create it dominates the runtime.
        bpy.ops.object.select_all(action='DESELECT')
        prev = None
        for name in names:
            d = bpy.data.objects[name]
            if prev: prev.select_set(False)
            d.select_set(True)
            bpy.context.view_layer.objects.active = d
            bpy.ops.sollumz.createarchetypefromselected()
            prev = d
        for a in yt.archetypes:
            a.texture_dictionary = ""    # textures are embedded in each .ydr
            a.lod_dist = LOD_DIST        # signs should read from a distance
        bpy.ops.sollumz.export_ytyp_io(directory=YDR, target_formats={'NATIVE'},
                                       target_versions={'GEN8'}, use_custom_settings=True)
    return len(names)


def ship():
    """Copy the exported stream assets into the resource."""
    os.makedirs(STREAM, exist_ok=True)
    import shutil
    n = 0
    for f in os.listdir(YDR):
        if f.endswith(".ydr") or f.endswith(".ytyp"):
            shutil.copy2(os.path.join(YDR, f), os.path.join(STREAM, f))
            n += 1
    return n


def purge():
    """Drop the scratch objects/meshes so repeated runs do not bloat the .blend."""
    coll = bpy.data.collections.get("AL_FiveM")
    if not coll:
        return 0
    n = 0
    for ob in list(coll.objects):
        me = ob.data
        bpy.data.objects.remove(ob)
        if isinstance(me, bpy.types.Mesh) and me.users == 0:
            bpy.data.meshes.remove(me)
        n += 1
    bpy.data.collections.remove(coll)
    return n


def main(styles=("painted", "neon"), clean=True):
    """Full FiveM export: every glyph, in both finishes. Colour is not baked.

    129 glyphs x 2 finishes is 258 drawables. Run it from Blender after
    build_alphabet3d.py has populated the scene.

    Order matters in two places:

      - archetypes for a set are appended *before* that set is purged, because
        add_archetypes() resolves names against live objects;
      - purging as we go keeps the object count flat, which matters because archetype
        creation slows down noticeably as the scene grows.
    """
    os.makedirs(YDR, exist_ok=True)

    if clean:
        # Model names are stable between runs, so a re-export overwrites the old
        # files -- but only for glyphs that actually export. Clearing first turns a
        # silent per-glyph failure into a missing model rather than a stale one left
        # over from the previous font, which is far easier to notice.
        for d in (YDR, STREAM):
            if not os.path.isdir(d):
                continue
            for f in os.listdir(d):
                if f.endswith(".ydr") or f.endswith(".ytyp"):
                    os.remove(os.path.join(d, f))

    total, first = 0, True
    for style in styles:
        names = export_style(style)
        add_archetypes(names, reset=first)
        first = False
        purge()
        total += len(names)
        print("  %-7s %3d models" % (style, len(names)), flush=True)

    save_ytyp()
    shipped = ship()
    print("exported %d models, shipped %d files to %s" % (total, shipped, STREAM))
    return total
