class_name SceneTransitionManager extends RefCounted

var old_transition_process_mode: Node.ProcessMode = Node.ProcessMode.PROCESS_MODE_INHERIT
var old_tree_pause_state: bool = false
var old_parent_process_mode: Node.ProcessMode = Node.ProcessMode.PROCESS_MODE_INHERIT

var current_transition: Node = null:
	get:
		return current_transition
	set(value):
		if current_transition != null:
			current_transition.process_mode = self.old_transition_process_mode
			if current_transition.tree_exiting.is_connected(self._on_transition_exiting):
				current_transition.tree_exiting.disconnect(self._on_transition_exiting)
		current_transition = value
		if current_transition != null:
			self.old_transition_process_mode = current_transition.process_mode
			current_transition.process_mode = Node.PROCESS_MODE_ALWAYS
			current_transition.tree_exiting.connect(self._on_transition_exiting)

func _init() -> void:
	pass

func is_transitioning() -> bool:
	return self.current_transition != null

func apply_transition(parent: Node, transition: Node, pause_parent: bool = true) -> void:
	assert(parent != null, "transition parent must not be null")
	assert(transition != null, "transition must not be null")
	assert(!self.is_transitioning(), "SceneTransitionManager is already running a scene transition")
	if transition == null:
		return
	self.current_transition = transition

	self.old_parent_process_mode = parent.process_mode
	if pause_parent:
		parent.process_mode = Node.PROCESS_MODE_DISABLED

	if parent.is_inside_tree():
		var tree: SceneTree = parent.get_tree()
		self.old_tree_pause_state = tree.paused
		if pause_parent:
			tree.paused = true

	parent.add_child(self.current_transition, false, Node.INTERNAL_MODE_BACK)

func _cleanup_transition(parent: Node, transition: Node) -> void:
	if transition != null && is_instance_valid(transition) && transition.is_inside_tree():
		await transition.tree_exited

	if parent != null:
		parent.process_mode = self.old_parent_process_mode
		if parent.is_inside_tree():
			var tree: SceneTree = parent.get_tree()
			tree.paused = self.old_tree_pause_state

func end_transition() -> void:
	var transition: Node = self.current_transition
	self.current_transition = null
	if transition == null:
		return

	var parent: Node = transition.get_parent()

	if transition.has_method(&"end_transition"):
		var e_sig: Variant = transition.call(&"end_transition")
		if e_sig is Signal:
			await e_sig
			transition.queue_free()
	else:
		transition.free()
		transition = null

	await self._cleanup_transition(parent, transition)

func _reparent_transition(p: Node, preserve_global_transform: bool) -> void:
	if self.current_transition != null:
		self.current_transition.reparent(p, preserve_global_transform)

func _on_transition_exiting() -> void:
	var transition: Node = self.current_transition
	self.current_transition = null
	var parent: Node = transition.get_parent()
	self._cleanup_transition(parent, transition)

## Whether the transition is ready for the old scene to be freed from beneath it
func is_transition_ready() -> bool:
	assert(self.current_transition != null, "tried to check readiness of inactive transition")
	var is_ready: Variant = self.current_transition.get(&"transition_is_ready")
	if is_ready == null:
		# if we can't find a `transition_is_ready` property, assume it's ready immediately
		return true
	return (is_ready is bool && is_ready) || (is_ready is Callable && (is_ready as Callable).call())

## Awaitable function that returns when the transition is ready for the old scene to be freed
func transition_ready() -> void:
	if self.is_transition_ready():
		return
	if self.current_transition.has_signal(&"transition_ready"):
		await self.current_transition.get(&"transition_ready")
