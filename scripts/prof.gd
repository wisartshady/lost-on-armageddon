class_name Prof
extends RefCounted

static var on:= OS.get_environment("OXWAG_PROF") != ""
static var acc:= {}
static var cnt:= {}
static var _t:= {}

static func b(label: String) -> void:
	if on:
		_t[label] = Time.get_ticks_usec()

static func e(label: String) -> void:
	if on and _t.has(label):
		acc[label] = acc.get(label, 0) + Time.get_ticks_usec() - _t[label]
		cnt[label] = cnt.get(label, 0) + 1

static func report(frames: int) -> String:
	var keys:= acc.keys()
	keys.sort_custom(func (a, b): return acc[a] > acc[b])
	var s:= ""
	for k in keys:
		s += "%s=%.2fms(x%d) " % [k, acc[k] / 1000.0 / maxf(frames, 1), cnt[k] / maxi(frames, 1)]
	acc.clear(); cnt.clear()
	return s
