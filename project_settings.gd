@tool
class_name SceneManagerSettings extends RefCounted

const ROOT_SCENE: String = "runtime/root_scene"

const DEFINITIONS: Dictionary = {
	ROOT_SCENE: {
		"value": "",
		"type": TYPE_STRING_NAME,
		"hint": PROPERTY_HINT_FILE,
		"hint_string": "PackedScene"
	}
}

static func prepare() -> void:
	for key: String in DEFINITIONS:
		var def: Dictionary = DEFINITIONS[key]
		var name: String = "scene_manager/%s" % key

		if !ProjectSettings.has_setting(name):
			ProjectSettings.set_setting(name, def.value)

		ProjectSettings.set_initial_value(name, def.value)

		var info: Dictionary = {
			"name": name,
			"type": def.type,
			"hint": def.get("hint", PROPERTY_HINT_NONE),
			"hint_string": def.get("hint_string", "")
		}
		ProjectSettings.add_property_info(info)

		ProjectSettings.set_as_basic(name, !def.has("is_advanced"))
		ProjectSettings.set_as_internal(name, def.has("is_hidden"))

static func get_setting(path: StringName, default: Variant) -> Variant:
	var full_path: String = "scene_manager/%s" % path
	if ProjectSettings.has_setting(full_path):
		var setting: Variant = ProjectSettings.get_setting(full_path)
		return setting
	else:
		return default

static func has_setting(path: StringName) -> bool:
	return ProjectSettings.has_setting("scene_manager/%s" % path)
