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
const CORNER_RADIUS = 50.0

func _ready() -> void:
	add_to_group("obstacle")

func setup_random() -> void:
	var template = shape_templates.pick_random()
	var raw_points = []
	
	# Scale points
	for pt in template:
		raw_points.append(pt * SCALE_FACTOR)
	
	# Round Corners
	var rounded_points = _round_corners(raw_points, CORNER_RADIUS)
	var final_points = PackedVector2Array(rounded_points)
	
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

func _round_corners(points: Array, radius: float) -> Array:
	var new_points = []
	var count = points.size()
	
	for i in range(count):
		var curr = points[i]
		var prev = points[(i - 1 + count) % count]
		var next = points[(i + 1) % count]
		
		var to_prev = (prev - curr).normalized()
		var to_next = (next - curr).normalized()
		
		# Prevent crossing if radius is too big for the edge
		var dist_prev = curr.distance_to(prev)
		var dist_next = curr.distance_to(next)
		var actual_radius = min(radius, min(dist_prev, dist_next) * 0.45)
		
		var p1 = curr + to_prev * actual_radius
		var p2 = curr + to_next * actual_radius
		
		new_points.append(p1)
		new_points.append(p2)
		
	return new_points
