extends StaticBody2D

# Continuous Shapes (Normalized points centered roughly at 0,0)
# Points should be defined in CLOCKWISE order for CollisionPolygon
var shape_templates = [
	# 1. The "Big Box"
	[Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)],
	# 2. The "Cross"
	[Vector2(-0.5, -1.5), Vector2(0.5, -1.5), Vector2(0.5, -0.5), Vector2(1.5, -0.5), Vector2(1.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, 1.5), Vector2(-0.5, 1.5), Vector2(-0.5, 0.5), Vector2(-1.5, 0.5), Vector2(-1.5, -0.5), Vector2(-0.5, -0.5)],
	# 3. The "L" (Thick)
	[Vector2(-1, -1.5), Vector2(0, -1.5), Vector2(0, 0.5), Vector2(1, 0.5), Vector2(1, 1.5), Vector2(-1, 1.5)],
	# 4. The "H" / "I" (Vertical Bar)
	[Vector2(-0.5, -2), Vector2(0.5, -2), Vector2(0.5, 2), Vector2(-0.5, 2)]
]

const SCALE_FACTOR = 400.0

func _ready() -> void:
	add_to_group("obstacle")

func setup_random() -> void:
	var template = shape_templates.pick_random()
	var final_points = PackedVector2Array()
	
	# Scale points
	for pt in template:
		final_points.append(pt * SCALE_FACTOR)
	
	# 1. Visual (Polygon2D)
	var poly = Polygon2D.new()
	poly.color = Color(0.15, 0.15, 0.15)
	poly.polygon = final_points
	add_child(poly)
	
	# 2. Collision (CollisionPolygon2D)
	var coll = CollisionPolygon2D.new()
	coll.polygon = final_points
	add_child(coll)

	# No Rotation (Always aligned vertically/horizontally)
	rotation = 0.0
