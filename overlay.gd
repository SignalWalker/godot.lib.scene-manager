class_name Overlay extends RefCounted

enum OverlayStatus {
	INACTIVE, ACTIVE,
	FINISHED
}

var stack: WeakRef = null:
	get:
		return stack
	set(value):
		assert(stack == null, "[SceneManager] tried to set stack on an Overlay that already had a stack")
		stack = value

var below: Overlay
var above_ref: WeakRef
var above: Overlay:
	get:
		if self.above_ref == null:
			return null
		return self.above_ref.get_ref() as Overlay
	set(value):
		self.above_ref = weakref(value)

var b_node: Node
var pause_below: bool
var below_process_mode: Node.ProcessMode

var node: Node
var status: OverlayStatus

signal activated(is_active: bool)
signal finished(n: Node)

func _init(s: OverlayStack, p_below: bool, base: Node, bel: Overlay, n: Node) -> void:

	self.stack = weakref(s)

	self.status = OverlayStatus.INACTIVE

	self.node = n
	self.node.process_mode = Node.PROCESS_MODE_PAUSABLE
	self.node.tree_exiting.connect(self._on_node_exiting)

	self.pause_below = p_below

	if bel == null:
		self.below = null
		self._set_b_node(base, base.process_mode)
	else:
		self._set_below(bel, bel.node.process_mode)

	self.above = null


func _activate() -> void:
	assert(self.status == OverlayStatus.INACTIVE, "tried to activate previously-activated overlay")
	self.status = OverlayStatus.ACTIVE
	self._update_b_node()
	self.activated.emit(true)

func _finish() -> void:
	assert(self.status == OverlayStatus.ACTIVE, "tried to finish inactive/previously-finished overlay")
	self.status = OverlayStatus.FINISHED

	var a: Overlay = self.above
	if a != null:
		# connect the overlay/node below this one to the above overlay
		a._reconnect(self.below, self.b_node, self.below_process_mode)
	else:
		# unpause? node below this one
		self._update_b_node()

	# inform stack that we're done
	var st: OverlayStack = self.stack.get_ref()
	if st != null:
		st._on_overlay_finishing(self)

	self.finished.emit(self.node)

func is_active() -> bool:
	return self.status == OverlayStatus.ACTIVE

func is_finished() -> bool:
	return self.status == OverlayStatus.FINISHED

func wait_active() -> Variant:
	match self.status:
		OverlayStatus.INACTIVE:
			return self.activated
		OverlayStatus.ACTIVE:
			return true
		OverlayStatus.FINISHED:
			return false
		_:
			assert(false, "unreachable")
			return null

func wait_finished() -> Variant:
	match self.status:
		OverlayStatus.INACTIVE:
			return self.finished
		OverlayStatus.ACTIVE:
			return self.finished
		OverlayStatus.FINISHED:
			return self.node
		_:
			assert(false, "unreachable")
			return null

func _reconnect(bel: Overlay, b: Node, b_mode: Node.ProcessMode) -> void:
	assert(b_node != null)
	self._set_below(bel, b_mode)
	if bel == null:
		self._set_b_node(b, b_mode)
	self._update_b_node()

func _set_below(b: Overlay, b_mode: Node.ProcessMode) -> void:
	self.below = b
	if self.below != null:
		self.below.above = self
		self._set_b_node(self.below.node, b_mode)
		self._update_b_node()

func _set_b_node(b: Node, b_mode: Node.ProcessMode) -> void:
	assert(b != null)
	self.b_node = b
	self.below_process_mode = b_mode

func _update_b_node() -> void:
	if self.b_node != null && is_instance_valid(self.b_node):
		if self.pause_below:
			if self.status == OverlayStatus.ACTIVE:
				self.b_node.process_mode = Node.ProcessMode.PROCESS_MODE_DISABLED
			elif self.status == OverlayStatus.FINISHED:
				self.b_node.process_mode = self.below_process_mode

func _on_node_exiting() -> void:
	if !self.is_finished():
		self._finish()
