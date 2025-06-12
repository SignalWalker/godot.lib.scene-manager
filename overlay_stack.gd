class_name OverlayStack extends RefCounted

var top: Overlay
var pushing_overlay: bool

func _init() -> void:
	self.reset()

func reset() -> void:
	self.clear()
	self.pushing_overlay = false

func clear() -> void:
	while self.top != null:
		self.pop_overlay()

func is_busy() -> bool:
	return self.pushing_overlay

## Get the index of the given node within the overlay stack
func get_index_of(n: Node) -> int:
	var id: int = n.get_instance_id()
	return self.stack.find_custom(func(ovl: Overlay) -> bool: return ovl.node.get_instance_id() == id)

## Pause the current scene in favor of some sub-scene, and return an Overlay object that can be used to keep track of the status of the overlay
func push_overlay(manager: SSceneManager, ovl: Variant, transition: Node, pause_below: bool, defer: bool, cache_mode: ResourceLoader.CacheMode) -> Overlay:
	assert(!self.is_busy(), "tried to push overlay while already pushing an overlay")
	var node: Node = manager._load_scene(ovl, false, cache_mode)
	if node == null:
		return
	self.pushing_overlay = true
	var overlay: Overlay = Overlay.new(self, pause_below, manager.current_scene, self.top, node)
	if defer:
		self._push_overlay.call_deferred(manager, overlay, transition)
	else:
		self._push_overlay(manager, overlay, transition)
	return overlay

## Pop the topmost overlay from the stack and remove it from the scene tree.
func pop_overlay() -> Node:
	if self.top == null:
		return null

	var top: Overlay = self.top
	var parent: Node = top.get_parent()
	if parent != null:
		parent.remove_child(top.node)

	return top.node

func _reparent_all(p: Node, preserve_global_transform: bool) -> void:
	var overlays: Array[Node] = []
	var t: Overlay = self.top
	while t != null:
		overlays.push_front(t.node)
		t = t.below
	for n: Node in overlays:
		n.reparent(p, preserve_global_transform)

func _push_overlay_deferred(manager: SSceneManager, overlay: Overlay) -> void:
	# update tree
	manager.root.add_child(overlay.node)
	manager._update_tree_current_scene()

	await manager.transition_manager.end_transition()

	# emit signals
	self.pushing_overlay = false
	overlay._activate()

func _push_overlay(manager: SSceneManager, overlay: Overlay, transition: Node = null) -> void:
	assert(manager.current_scene != null, "[SceneManager] tried to push overlay while current scene is null (during scene change?)")

	if transition != null:
		manager.transition_manager.apply_transition(manager.root, transition)

	self.top = overlay

	if transition != null:
		await manager.transition_manager.transition_ready()
		self._push_overlay_deferred.call_deferred(manager, overlay)
	else:
		self._push_overlay_deferred(manager, overlay)

func _on_overlay_finishing(overlay: Overlay) -> void:
	if self.top == overlay:
		self.top = overlay.below
		self.top_changed.emit(self.top)
