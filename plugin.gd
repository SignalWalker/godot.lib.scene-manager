@tool
extends EditorPlugin

func get_plugin_path() -> String:
	return get_script().resource_path.get_base_dir()

func _enable_plugin() -> void:
	if !type_exists(&"ThreadPool"):
		printerr("SceneManager requires ThreadPool")
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
