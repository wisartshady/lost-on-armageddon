"""Cut the window openings out of the vehicle shells (run: python3 tools/blender/cut_windows.py [model ...]).

The original car bodies are closed shells: the paint surface runs on behind every pane and the glass is a skin on
top. For the see-through glass the shell has to be opened exactly along each pane's outline, otherwise ragged
triangles of paint show inside the windows. The glass faces are pulled out into a thin solid and subtracted from
the body with an exact boolean. Output: /home/claude/work/veh_cut/<model>.glb (body without glass, attributes kept).
"""
import bpy, bmesh, os, sys, glob

SRC = '/home/claude/work/veh'
OUT = '/home/claude/work/veh_cut'


def run(model):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, model + '.glb'))
    body = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
    me = body.data
    uv2 = me.uv_layers[1]
    glass_polys = set()
    for p in me.polygons:
        pid = int(round(uv2.data[p.loop_indices[0]].uv.x))
        if pid == 1:
            glass_polys.add(p.index)
    # cutter: a copy of the glass panes, made solid (7 cm, centred on the pane)
    cut = body.copy()
    cut.data = me.copy()
    bpy.context.scene.collection.objects.link(cut)
    bm = bmesh.new()
    bm.from_mesh(cut.data)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in glass_polys], context='FACES')
    bm.to_mesh(cut.data)
    bm.free()
    sol = cut.modifiers.new('solid', 'SOLIDIFY')
    sol.thickness = 0.07
    sol.offset = 0.0
    sol.use_even_offset = True
    # body without its glass faces
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index in glass_polys], context='FACES')
    bm.to_mesh(me)
    bm.free()
    bo = body.modifiers.new('cut', 'BOOLEAN')
    bo.operation = 'DIFFERENCE'
    bo.solver = 'EXACT'
    bo.object = cut
    bo.use_hole_tolerant = True
    bo.use_self = False
    bpy.context.view_layer.objects.active = body
    for o in bpy.context.scene.objects:
        o.select_set(o == body)
    bpy.ops.object.modifier_apply(modifier='cut')
    bpy.data.objects.remove(cut, do_unlink=True)
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, model + '.glb'), use_selection=True, export_format='GLB',
                              export_texcoords=True, export_normals=True, export_vertex_color='ACTIVE',
                              export_all_vertex_colors=True, export_materials='NONE', export_yup=True)
    print('CUT', model, len(body.data.polygons))


for m in (sys.argv[1:] or sorted(os.path.basename(p)[:-4] for p in glob.glob(os.path.join(SRC, '*.glb')))):
    run(m)
