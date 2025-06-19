@tool
extends EditorPlugin

func get_plugin_path() -> String:
	return get_script().resource_path.get_base_dir()

static func get_script_props_by_name(name: String) -> Dictionary:
	for cls: Dictionary in ProjectSettings.get_global_class_list():
		if cls["class"] == name:
			return cls
	push_error("could not find type {0}".format([name]))
	return {}

static func script_exists(name: String) -> bool:
	return !get_script_props_by_name(name).is_empty()

func _enable_plugin() -> void:
	if !script_exists("ThreadPool"):
		push_error("SceneManager requires ThreadPool")
		return
	add_autoload_singleton("SceneManager", get_plugin_path() + "/scene_manager.gd")

func _disable_plugin() -> void:
	remove_autoload_singleton("SceneManager")

func _enter_tree() -> void:
	if !Engine.is_editor_hint():
		return
	Engine.set_meta(&"SceneManagerPlugin", self)
	SceneManagerSettings.prepare()

func _exit_tree() -> void:
	if !Engine.is_editor_hint():
		return
	Engine.remove_meta("SceneManagerPlugin")
