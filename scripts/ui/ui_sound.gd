class_name UiSound
extends RefCounted

static var _player: AudioStreamPlayer = null
static var _cache:= {}
const SETS:= {
	"hover": ["select_001", "select_002"], "click": ["click_001", "click_002"], "back": ["back_001", "back_002"],
	"switch": ["switch_001", "switch_002", "switch_003"], "confirm": ["confirmation_001"], "scroll": ["scroll_001", "scroll_002"],
}

static func play(kind: String, vol:= -10.0) -> void:
	if _player == null or not is_instance_valid(_player):
		var tree:= Engine.get_main_loop() as SceneTree
		if tree == null:
			return
		_player = AudioStreamPlayer.new()
		_player.bus = "SFX"
		_player.process_mode = Node.PROCESS_MODE_ALWAYS
		_player.max_polyphony = 4
		tree.root.add_child.call_deferred(_player)
		return
	var names: Array = SETS.get(kind, SETS["click"])
	var n: String = names[randi() % names.size()]
	if not _cache.has(n):
		_cache[n] = load("res://assets/audio/ui/%s.ogg" % n)
	_player.stream = _cache[n]
	_player.volume_db = vol
	_player.play()
