class_name SceneTransitionManager extends RefCounted

class SceneTransition extends RefCounted:
	var trans: AnimationPlayer

	enum TransitionStatus {
		INACTIVE,
		STARTED,
		READY,
		FINISHED
	}

	var status: TransitionStatus

	signal started()
	signal ready()
	signal finished()

	static func _is_start_animation(player: AnimationPlayer, name: StringName) -> bool:
		return name == &"transition_start" || (player.autoplay != "" && name == player.autoplay)

	func _has_animation(name: StringName) -> bool:
		return self.trans.get_animation_list().find(name) >= 0

	func _init(t: AnimationPlayer) -> void:
		self.status = TransitionStatus.INACTIVE
		self.trans = t
		self.trans.animation_started.connect(self._on_animation_started)
		self.trans.animation_finished.connect(self._on_animation_finished)
		self.trans.tree_exiting.connect(self._on_animation_exiting)

	func has_ready_step() -> bool:
		return self._has_animation(&"transition_ready")

	func has_end_step() -> bool:
		return self._has_animation(&"transition_end")

	func is_ready() -> bool:
		return self.status == TransitionStatus.READY || self.status == TransitionStatus.FINISHED

	func is_finished() -> bool:
		return self.status == TransitionStatus.FINISHED

	## Start the transition animation and return whether the transition is ready for scene swap
	func start() -> bool:
		self.status = TransitionStatus.STARTED
		self.trans.process_mode = Node.ProcessMode.PROCESS_MODE_ALWAYS
		# check for autoplay and play that if it exists
		if self.trans.autoplay != "":
			self.trans.play(self.trans.autoplay)
			self.started.emit()
			return self.trans.autoplay == "transition_ready"
		# otherwise, try playing "transition_start"
		assert(self._has_animation(&"transition_start"), "[SceneManager] scene transition AnimationPlayer must have an autoplay animation or an animation named transition_start")
		self.trans.play(&"transition_start")
		self.started.emit()
		return false

	## Return once the transition is ready for scene swap
	func wait_ready() -> void:
		if self.is_ready():
			return
		await self.ready

	## Return once the transition is finished
	func wait_finished() -> void:
		if self.is_finished():
			return
		await self.finished

	func _make_ready() -> void:
		self.status = TransitionStatus.READY
		self.ready.emit()

	func _make_finished() -> void:
		if self.status == TransitionStatus.STARTED:
			self._make_ready()
		self.status = TransitionStatus.FINISHED
		self.finished.emit()

	func finish() -> void:
		await self.wait_ready()
		if self.has_end_step():
			self.trans.play(&"transition_end")
			await self.wait_finished()
		else:
			self._make_finished()

	func _on_animation_started(name: StringName) -> void:
		if name == &"transition_ready":
			self._make_ready()
		elif name == &"transition_end" && self.status == TransitionStatus.STARTED:
			self._make_ready()

	func _on_animation_finished(name: StringName) -> void:
		if _is_start_animation(self.trans, name):
			if self.has_ready_step():
				self.trans.play(&"transition_ready")
			elif self.has_end_step():
				self.trans.play(&"transition_end")
			else:
				self._make_finished()
		elif name == &"transition_ready":
			if self.has_end_step():
				self.trans.play(&"transition_end")
			else:
				self._make_finished()
		elif name == &"transition_end":
			self._make_finished()

	func _on_animation_exiting() -> void:
		self._make_finished()

var old_tree_pause_state: bool = false
var old_parent_process_mode: Node.ProcessMode = Node.ProcessMode.PROCESS_MODE_INHERIT

var current_transition: SceneTransition = null

func _init() -> void:
	pass

func is_transitioning() -> bool:
	return self.current_transition != null

func _start_transition_animation() -> void:
	pass

func apply_transition(parent: Node, transition: AnimationPlayer, pause_parent: bool = true) -> void:
	assert(parent != null, "transition parent must not be null")
	assert(transition != null, "transition must not be null")
	assert(!self.is_transitioning(), "SceneTransitionManager is already running a scene transition")

	if transition == null:
		return

	self.current_transition = SceneTransition.new(transition)
	self.current_transition.start()

	self.old_parent_process_mode = parent.process_mode
	if pause_parent:
		parent.process_mode = Node.PROCESS_MODE_DISABLED

	if parent.is_inside_tree():
		var tree: SceneTree = parent.get_tree()
		self.old_tree_pause_state = tree.paused
		if pause_parent:
			tree.paused = true

	parent.add_child(self.current_transition.trans, false, Node.INTERNAL_MODE_BACK)

func _cleanup_transition(parent: Node) -> void:
	if parent != null:
		parent.process_mode = self.old_parent_process_mode
		if parent.is_inside_tree():
			var tree: SceneTree = parent.get_tree()
			tree.paused = self.old_tree_pause_state

func end_transition() -> void:
	var transition: SceneTransition = self.current_transition
	self.current_transition = null
	if transition == null:
		return

	var parent: Node = transition.trans.get_parent()

	if transition.is_finished():
		transition.trans.free()
	else:
		await transition.finish()
		transition.trans.queue_free()

	self._cleanup_transition(parent)

func _reparent_transition(p: Node, preserve_global_transform: bool) -> void:
	if self.current_transition != null:
		self.current_transition.trans.reparent(p, preserve_global_transform)

## Whether the transition is ready for the old scene to be freed from beneath it
func is_transition_ready() -> bool:
	assert(self.current_transition != null, "tried to check readiness of inactive transition")
	return self.current_transition.is_ready()

## Awaitable function that returns when the transition is ready for the old scene to be freed
func wait_ready() -> void:
	await self.current_transition.wait_ready()
