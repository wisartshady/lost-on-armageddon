extends SceneTree
## Exports a character scene (skinned meshes + skeleton) to glTF for editing in Blender.
## Run: godot --headless --path . --script res://tools/export_character_glb.gd -- <model> <out.glb>

func _init() -> void:
	var args:= OS.get_cmdline_user_args()
	var model:= args[0] if args.size() > 0 else "vaynara"
	var out:= args[1] if args.size() > 1 else "/home/claude/work/vay/%s.glb" % model
	var inst: Node = load("res://assets/models/characters/%s.scn" % model).instantiate()
	var doc:= GLTFDocument.new()
	var st:= GLTFState.new()
	var e:= doc.append_from_scene(inst, st)
	if e == OK:
		e = doc.write_to_filesystem(st, out)
	print("EXPORT ", model, " -> ", out, " ", e)
	inst.free()
	quit()
