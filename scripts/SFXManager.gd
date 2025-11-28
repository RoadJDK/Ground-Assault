extends Node

# --- SFX CACHE ---
var sfx_player_shot = preload("res://sfx/PlayerShot.wav")
var sfx_ranged_shot = preload("res://sfx/RangedShot.wav")
var sfx_turret_mg = preload("res://sfx/TurretMg.wav")
var sfx_turret_how = preload("res://sfx/TurretHowitzer.wav")
var sfx_rocket_shot = preload("res://sfx/RocketShots.wav")
var sfx_hit_how = preload("res://sfx/HitHowitzer.wav")
var sfx_hit_mg = preload("res://sfx/HitMg.wav")
var sfx_melee_0 = preload("res://sfx/Melee0.wav")
var sfx_melee_1 = preload("res://sfx/Melee1.wav")
var sfx_melee_2 = preload("res://sfx/Melee2.wav")
var sfx_factory_spawn = preload("res://sfx/FactorySpawn.mp3")
var sfx_building_destroy = preload("res://sfx/BuildingDestroy.wav")
var sfx_building_build = preload("res://sfx/BuildingBuild.wav")

var _last_hit_mg_time: int = 0

func play_sound(stream: AudioStream, position: Vector2 = Vector2.ZERO, volume_db: float = 0.0, pitch_scale: float = 1.0, overview_dampen: float = 30.0):
	if stream == null: return
	
	var dist = 4000.0 # Default Close View Range
	
	# Global Dampening in Overview Mode
	var cam = get_viewport().get_camera_2d()
	if cam and "is_overview_mode" in cam and cam.is_overview_mode:
		volume_db -= overview_dampen # Global dampening
		dist = 20000.0 # Expand range to hear full map
	
	var player = AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.global_position = position
	player.max_distance = dist 
	player.panning_strength = 3.75 # Exaggerated stereo width
	player.bus = "SFX" 
	
	get_tree().root.add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

# --- SPECIFIC HELPERS ---

func play_player_shot(pos: Vector2, extra_db: float = 0.0):
	# Less dampening for player in overview (8dB instead of 18dB)
	play_sound(sfx_player_shot, pos, -5.0 + extra_db, randf_range(0.95, 1.05), 8.0)

func play_ranged_shot(pos: Vector2):
	# Significantly quieter to prevent oversteering with mass units
	play_sound(sfx_ranged_shot, pos, -15.0, randf_range(0.9, 1.1))

func play_turret_mg(pos: Vector2):
	# Louder
	play_sound(sfx_turret_mg, pos, -2.0, randf_range(0.98, 1.02))

func play_turret_howitzer(pos: Vector2):
	# Louder
	play_sound(sfx_turret_how, pos, 2.0, randf_range(0.95, 1.05))

func play_rocket_shot(pos: Vector2):
	play_sound(sfx_rocket_shot, pos, -4.0, randf_range(0.9, 1.1))

func play_hit_howitzer(pos: Vector2):
	# Louder Explosion
	play_sound(sfx_hit_how, pos, 2.0, randf_range(0.8, 1.2))

func play_hit_mg(pos: Vector2):
	# Rate Limit to prevent oversteering
	var now = Time.get_ticks_msec()
	if now - _last_hit_mg_time < 50: return
	_last_hit_mg_time = now
	
	play_sound(sfx_hit_mg, pos, -6.0, randf_range(0.8, 1.2))

func play_melee_attack(pos: Vector2):
	var sfx_list = [sfx_melee_0, sfx_melee_1, sfx_melee_2]
	var pick = sfx_list.pick_random()
	play_sound(pick, pos, -2.0, randf_range(0.9, 1.1))

func play_factory_spawn(pos: Vector2):
	play_sound(sfx_factory_spawn, pos, -5.0, randf_range(0.95, 1.05))

func play_building_destroy(pos: Vector2):
	play_sound(sfx_building_destroy, pos, 4.0, randf_range(0.9, 1.1))

func play_building_build(pos: Vector2):
	play_sound(sfx_building_build, pos, -2.0, 1.0)
