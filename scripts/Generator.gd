extends Building

@export var gold_per_tick: int = 2

func _ready() -> void:
	super._ready()
	# Ensure there is a timer node, or create one if missing
	var timer = get_node_or_null("Timer")
	if not timer:
		timer = Timer.new()
		timer.wait_time = 1.0
		timer.autostart = true
		add_child(timer)
	
	if not timer.is_connected("timeout", _on_timer_timeout):
		timer.timeout.connect(_on_timer_timeout)

func _on_timer_timeout() -> void:
	# Find Main to add gold
	var main = get_tree().root.find_child("Main", true, false)
	# Updated to pass faction to Main
	if main and main.has_method("add_gold"):
		var amount = 200
		main.add_gold(amount, self.faction)
