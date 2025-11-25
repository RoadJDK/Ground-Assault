extends CanvasLayer

signal build_requested(building_type)

@onready var gold_label = find_child("GoldLabel", true, false)

# Map names to button nodes (Assuming standard naming convention or setting up manually)
# You might need to adjust paths based on your scene tree
@onready var btn_generator = find_child("BtnGenerator", true, false)
@onready var btn_turret = find_child("BtnTurret", true, false)
@onready var btn_factory = find_child("BtnFactory", true, false)
@onready var btn_shield = find_child("BtnShield", true, false)

func _ready() -> void:
	pass

func update_gold_display(amount: int) -> void:
	if gold_label:
		gold_label.text = "Gold: " + str(amount)

# New function to highlight buttons
func highlight_tool(type_name: String) -> void:
	var buttons = [btn_generator, btn_turret, btn_factory, btn_shield]
	
	for btn in buttons:
		if btn:
			btn.modulate = Color.WHITE # Reset
			
	var target_btn = null
	match type_name:
		"Generator": target_btn = btn_generator
		"Turret": target_btn = btn_turret
		"Factory": target_btn = btn_factory
		"Shield": target_btn = btn_shield
	
	if target_btn:
		target_btn.modulate = Color.YELLOW # Highlight Color

func _on_btn_generator_pressed() -> void:
	emit_signal("build_requested", "Generator")

func _on_btn_turret_pressed() -> void:
	emit_signal("build_requested", "Turret")

func _on_btn_factory_pressed() -> void:
	emit_signal("build_requested", "Factory")

func _on_btn_shield_pressed() -> void:
	emit_signal("build_requested", "Shield")
