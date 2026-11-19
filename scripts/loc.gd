extends Node

const LOCALES:= ["tr", "en", "de"]
const LANG_NAMES:= {"tr": "Türkçe", "en": "English", "de": "Deutsch"}

func _ready() -> void:
	var txt:= FileAccess.get_file_as_string("res://data/i18n.json")
	var data = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("i18n.json could not be parsed")
		return
	for loc in LOCALES:
		var t:= Translation.new()
		t.locale = loc
		for key in data:
			t.add_message(key, data[key].get(loc, data[key].get("tr", key)))
		TranslationServer.add_translation(t)
	TranslationServer.set_locale(Settings.language)
