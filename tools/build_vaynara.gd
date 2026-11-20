extends SceneTree
## Swaps Vaynara's garments for the ones from tools/blender/vaynara_outfit.py, on the original skeleton.
## The new meshes keep their vertex positions (model space is the same) and their skin weights by bone NAME; they
## are bound with the original Skin, so the animation library keeps working unchanged.
## Run: godot --headless --path . --script res://tools/build_vaynara.gd

const BASE:= "res://tools/assets/vaynara_base.scn"        # the v0.2.3 model (head, hair, hands, skeleton)
const OUTFIT:= "/home/claude/work/vay/vaynara_outfit.glb"
const OUT:= "res://assets/models/characters/vaynara.scn"
const REMOVE:= ["Hoodie", "Jeans", "Boots", "Collar", "Hood", "Strings"]
# material slot per garment (scripts/actors/character.gd: _material)
const SLOT:= {"Torso": "skin_flat", "CropTop": "crop", "Hoodie": "hoodie", "Zipper": "zipper", "Strings": "string",
	"Jeans": "denim", "Boots": "leather", "Metal": "metal"}


func _bind_names(skin: Skin, sk: Skeleton3D) -> Array:
	var out:= []
	for i in skin.get_bind_count():
		var n:= String(skin.get_bind_name(i))
		if n == "":
			n = sk.get_bone_name(skin.get_bind_bone(i))
		out.append(n)
	return out


func _init() -> void:
	var root: Node3D = load(BASE).instantiate()
	var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	var ref: MeshInstance3D = sk.get_node("Hoodie")
	var skin: Skin = ref.skin
	var names:= _bind_names(skin, sk)
	var index_of:= {}
	for i in names.size():
		index_of[names[i]] = i
	for n in REMOVE:
		var node:= sk.get_node_or_null(n)
		if node:
			sk.remove_child(node)
			node.free()
	var doc:= GLTFDocument.new()
	var st:= GLTFState.new()
	if doc.append_from_file(OUTFIT, st) != OK:
		push_error("cannot read " + OUTFIT)
		quit(1)
		return
	var src:= doc.generate_scene(st)
	var src_sk: Skeleton3D = src.find_children("*", "Skeleton3D", true, false)[0]
	var nodes:= src.find_children("*", "ImporterMeshInstance3D", true, false)
	nodes.append_array(src.find_children("*", "MeshInstance3D", true, false))
	for n in nodes:
		var am: ArrayMesh = n.mesh.get_mesh() if n.mesh is ImporterMesh else n.mesh
		var nskin: Skin = n.skin
		var nnames:= _bind_names(nskin, src_sk)
		var remap:= PackedInt32Array()
		for nm in nnames:
			if not index_of.has(nm):
				push_error("bone not in the original skin: " + nm)
			remap.append(index_of.get(nm, 0))
		var out:= ArrayMesh.new()
		for s in am.get_surface_count():
			var arr:= am.surface_get_arrays(s)
			var b: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			for k in b.size():
				b[k] = remap[b[k]]
			arr[Mesh.ARRAY_BONES] = b
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var src_mat:= am.surface_get_material(s)
			var mat:= StandardMaterial3D.new()
			mat.resource_name = SLOT.get(String(n.name), src_mat.resource_name if src_mat else "cloth")
			out.surface_set_material(s, mat)
		var mi:= MeshInstance3D.new()
		mi.name = n.name
		mi.mesh = out
		mi.skin = skin
		sk.add_child(mi)
		mi.owner = root
		mi.skeleton = NodePath("..")
		print("MESH ", mi.name, " ", out.get_aabb(), " mat ", out.surface_get_material(0).resource_name)
	var ps:= PackedScene.new()
	ps.pack(root)
	var e:= ResourceSaver.save(ps, OUT, ResourceSaver.FLAG_COMPRESS)
	print("SAVED ", OUT, " ", e)
	src.free()
	root.free()
	quit()
