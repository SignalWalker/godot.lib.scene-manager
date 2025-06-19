class_name SSceneManager extends Node

var scene_load_pool: ThreadPool = null

var root: Viewport:
	get:
		return root
	set(value):
		root = value
		self._reparent_to_root.call_deferred()

var current_scene: Node = null:
	get:
		return current_scene
	set(value):
		current_scene = value
		if current_scene != null:
			if current_scene.get_parent() == null:
				self.root.add_child(current_scene)
			elif !self.root.is_ancestor_of(current_scene):
				push_error("set SceneManager.current_scene to scene that is not descendant of SceneManager.root; reparenting...")
				current_scene.reparent(self.root, false)
		self._update_tree_current_scene()

var swapping_scenes: bool = false

var overlays: OverlayStack

var transition_manager: SceneTransitionManager

## Emitted after the base scene is changed
signal scene_changed(scene: Node)

func _init() -> void:
	self.scene_load_pool = ThreadPool.new(1)
	self.overlays = OverlayStack.new()
	self.transition_manager = SceneTransitionManager.new()

func _ready() -> void:
	var tree: SceneTree = self.get_tree()
	self.root = tree.root
	self.current_scene = tree.current_scene

func _reparent_to_root() -> void:
	if self.current_scene != null:
		self.current_scene.reparent(root, false)
	self.overlays._reparent_all(root, false)
	self.transition_manager._reparent_transition(root, false)

func _update_tree_current_scene() -> void:
	var topmost: Node = self.topmost_scene()
	if topmost != null:
		var tree: SceneTree = self.get_tree()
		var p: Node = topmost.get_parent()
		if p == tree.root:
			self.get_tree().current_scene = topmost
	else:
		push_error("could not update tree.current_scene: no transition, no overlay, and SceneManager.current_scene is null")

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
		return self.current_scene

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

	var old_scene: Node = self.current_scene

	if transition != null:
		# start the scene transition
		self.transition_manager.apply_transition(self.root, transition)
		# swap the old scene out
		self.current_scene = null
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
	self.current_scene = new_scene

	# tell the transition to end, and wait for it to do so...
	await self.transition_manager.end_transition()

	# allow scene to change
	self.swapping_scenes = false
	# emit scene change signal
	self.scene_changed.emit(current_scene)

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
