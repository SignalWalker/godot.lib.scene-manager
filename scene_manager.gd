class_name SSceneManager extends Node

const SMSettings := preload("./project_settings.gd")

var scene_load_pool: ThreadPool = null

var _root_scene_packed: PackedScene = null

## The root node of the scene containing the root node of the effective scene tree
var _root_scene: Node = null

## The root node of the scene tree (may be the same as _root_scene)
var _root: Node = null

var _current_scene: Node = null

var swapping_scenes: bool = false

var overlays: OverlayStack

var transition_manager: SceneTransitionManager

## Emitted after the base scene is changed
signal scene_changed(scene: Node)

func _init() -> void:
	self.scene_load_pool = ThreadPool.new(1)

	self.overlays = OverlayStack.new()
	self.transition_manager = SceneTransitionManager.new()


	if SMSettings.has_setting(SMSettings.ROOT_SCENE):
		var root_scene_path := SMSettings.get_setting(SMSettings.ROOT_SCENE, null) as String
		self._root_scene_packed = load(root_scene_path)
		if self._root_scene_packed != null:
			self._root_scene = self._root_scene_packed.instantiate()

			if self._root_scene.has_method(&"get_scene_manager_root"):
				self._root = self._root_scene.call(&"get_scene_manager_root")
				if self._root == null:
					push_error("SceneManager._root_scene.get_scene_manager_root() returned null")
					self._root = self._root_scene
			else:
				self._root = self._root_scene
		else:
			push_error("could not load scene from path {0}".format([root_scene_path]))

func _enter_tree() -> void:
	# set the root scene if necessary
	if self._root_scene == null:
		var tree: SceneTree = self.get_tree()
		self._root_scene = tree.root
		self._root = tree.root

	assert(self._root_scene != null)
	assert(self._root != null)

func _ready() -> void:
	# move whatever the engine decided was the current scene to our root
	self._post_ready.call_deferred()

func _post_ready() -> void:
	print("post_ready")
	var tree := self.get_tree()
	var c := tree.current_scene
	c.get_parent().remove_child(c)

	tree.root.add_child(self._root_scene)
	self._set_current_scene(c)

func _set_current_scene(s: Node) -> Node:
	print("_set_current_scene")
	var old := self._current_scene

	self._current_scene = s

	if self._current_scene != null:
		print("buh")
		var p := self._current_scene.get_parent()
		if p != null:
			push_error("setting SceneManager._current_scene to one that already has a parent; reparenting...")
			p.remove_child(self._current_scene)

		if old == null:
			self._root.add_child(self._current_scene)
		else:
			assert(old.get_parent() == self._root)
			old.add_sibling(self._current_scene)

	# if old != null:
	# 	self._root.remove_child(old)

	return old

func get_current_scene() -> Node:
	return self._current_scene

func get_root() -> Node:
	return self._root

# func _reparent_to_root() -> void:
# 	if self._current_scene != null:
# 		self._current_scene.reparent(self._root, false)
# 	self.overlays._reparent_all(self._root, false)
# 	self.transition_manager._reparent_transition(self._root, false)

# func _update_tree_current_scene() -> void:
# 	var topmost: Node = self.topmost_scene()
# 	if topmost != null:
# 		var tree: SceneTree = self.get_tree()
# 		var p: Node = topmost.get_parent()
# 		if p == tree.root:
# 			self.get_tree().current_scene = topmost
# 	else:
# 		push_error("could not update tree.current_scene: no transition, no overlay, and SceneManager.current_scene is null")

func is_changing_scene() -> bool:
	return self.overlays.is_busy() || self.swapping_scenes

func is_busy() -> bool:
	return self.transition_manager.is_transitioning() || self.is_changing_scene()

## Return the topmost scene managed by this. Ordered by priority, this will be:
## - The current transition, if there is one
## - The topmost overlay, if there is one
## - The current base scene
func topmost_scene() -> Node:
	if self.transition_manager.is_transitioning():
		return self.transition_manager.current_transition.trans
	elif self.overlays.top != null:
		return self.overlays.top.node
	else:
		return self._current_scene

## Swap to a new scene without clearing overlays.
func swap_scene(target: Variant, transition: AnimationPlayer = null, defer: bool = true) -> void:
	assert(!self.is_changing_scene(), "swap_scene() called during scene change")

	var t: Variant = self._load_scene(target, true)
	if t == null:
		# already printed errors
		return

	self.swapping_scenes = true

	if defer:
		self._swap_scene.call_deferred(t, transition)
	else:
		self._swap_scene(t, transition)

## Clear overlays and swap to a new scene.
func change_scene(target: Variant, transition: AnimationPlayer = null, defer: bool = true) -> void:
	assert(!self.is_changing_scene(), "change_scene() called during scene change")

	var t: Variant = self._load_scene(target, true)
	if t == null:
		# already printed errors
		return

	self.swapping_scenes = true

	if defer:
		self._change_scene.call_deferred(t, transition)
	else:
		self._change_scene(t, transition)

## Pause the current scene in favor of some sub-scene, and return an Overlay object that can be used to keep track of the status of the overlay
func push_overlay(ovl: Variant, transition: AnimationPlayer = null, pause_below: bool = true, defer: bool = true, cache_mode: ResourceLoader.CacheMode = ResourceLoader.CacheMode.CACHE_MODE_REUSE) -> Overlay:
	return self.overlays.push_overlay(self, ovl, transition, pause_below, defer, cache_mode)

func _swap_scene(target: Variant, transition: AnimationPlayer) -> void:
	# Whether we'll need to defer the call to _swap_scene_resolved. It's assumed that we enter this function
	# while it's safe to directly modify the tree, but any awaits will force us to defer til the next time it's safe.
	var must_defer: bool = false

	var old_scene: Node = self._current_scene

	if transition != null:
		# start the scene transition
		self.transition_manager.apply_transition(self._root, transition)
		# swap the old scene out
		self._set_current_scene(null)
		if self.transition_manager.is_transition_ready():
			# transition is already ready for the old scene to be swapped out
			# we never awaited, so we're still safe to directly free the old scene
			old_scene.free()
		else:
			# wait til the transition is ready for the old scene to be swapped out
			await self.transition_manager.wait_ready()
			# we awaited, so we'll have to defer the next step now...
			must_defer = true
			# queue freeing the old scene (we awaited, so it's not safe now to directly free it)
			old_scene.queue_free()
		# unset old_scene so we don't free it again in the next step
		old_scene = null

	# resolve the new scene
	var new_scene: Node
	if target is ThreadPool.TaskResult:
		# await scene load...
		new_scene = await (target as ThreadPool.TaskResult).get_result_async()
		# awaited, so we'll have to defer the next step
		must_defer = true
	else:
		assert(target is Node, "somehow, target is neither a TaskResult or a Node")
		new_scene = target as Node

	if must_defer:
		# we awaited at some point above, so we'll need to defer this until it's safe again to directly modify the tree
		self._swap_scene_resolved.call_deferred(old_scene, new_scene)
	else:
		# we never awaited above, so we can continue directly to the next step
		self._swap_scene_resolved(old_scene, new_scene)

func _swap_scene_resolved(old_scene: Node, new_scene: Node) -> void:
	if old_scene != null:
		assert(is_instance_valid(old_scene), "old_scene has already been freed...?")
		# didn't free the old scene in the previous step, so we'll free it now
		old_scene.free()

	# swap in the new scene
	self._set_current_scene(new_scene)

	# tell the transition to end, and wait for it to do so...
	await self.transition_manager.end_transition()

	# allow scene to change
	self.swapping_scenes = false
	# emit scene change signal
	self.scene_changed.emit(self._current_scene)

func _change_scene(target: Variant, transition: AnimationPlayer) -> void:
	# clear overlays
	self.overlays.clear()
	# swap scene
	self._swap_scene(target, transition)

func _load_scene_threaded(path: String, cache_mode: ResourceLoader.CacheMode) -> ThreadPool.TaskResult:
	ResourceLoader.load_threaded_request(path, "PackedScene", true, cache_mode)
	return self.scene_load_pool.enqueue(func() -> Node:
		return (ResourceLoader.load_threaded_get(path) as PackedScene).instantiate()
	)

## Returns either a Node, a ThreadPool.TaskResult returning a Node, or null on failure.
func _load_scene(scene: Variant, threaded: bool = false, cache_mode: ResourceLoader.CacheMode = ResourceLoader.CacheMode.CACHE_MODE_IGNORE) -> Variant:
	if scene == null:
		push_error("could not load scene: null parameter")
		return null
	# load from path...
	if scene is String or scene is StringName:
		var path: String = scene as String
		if not ResourceLoader.exists(path, "PackedScene"):
			push_error("could not load scene: PackedScene not found at given path: ", path)
			return null
		if threaded:
			return self._load_scene_threaded(path, cache_mode)
		else:
			scene = ResourceLoader.load(path, "PackedScene", cache_mode)
	# instantiate packed scene...
	if scene is PackedScene:
		var ts: PackedScene = scene as PackedScene
		if !ts.can_instantiate():
			push_error("could not load scene: can't instantiate ", ts)
			return null
		scene = ts.instantiate()
	# return the scene root node
	if scene is Node:
		return scene
	else:
		push_error("could not load scene: not a Node: ", scene)
		return null
