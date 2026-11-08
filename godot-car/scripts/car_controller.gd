extends CharacterBody3D

const MAX_SPEED := 34.0
const REVERSE_SPEED := 8.0
const ACCELERATION := 9.5
const BRAKING := 23.0
const STEERING_ANGLE := 0.43
var road_grid_spacing := 0.0
var wheel_radius := 0.48
var speed := 0.0
var enabled := false
var steering := 0.0
var interpolation_reset_tick := -10
var visual: Node3D
var wheels: Array[Node3D] = []
var front_pivots: Array[Node3D] = []
var lights:Node3D

func setup(model: Node3D) -> void:
	wheels.clear()
	front_pivots.clear()
	visual = model
	for label in ["FL", "FR"]:
		var pivot := model.get_node("CarModel/Steering_" + label) as Node3D
		front_pivots.append(pivot)
		wheels.append(pivot.get_node("Wheel_" + label))
	for label in ["RL", "RR"]:
		wheels.append(model.get_node("CarModel/Wheel_" + label))
	lights=Node3D.new()
	lights.set_script(load("res://scripts/vehicle_lights.gd"))
	model.add_child(lights)
	lights.setup(model,self)
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(48)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	# Refresh the client-side interpolation pose before clearing its history.
	force_update_transform()
	get_global_transform_interpolated()
	reset_physics_interpolation()
	interpolation_reset_tick = Engine.get_physics_frames()

func reset_at(pos: Vector3, yaw: float = 0.0) -> void:
	position = pos
	rotation = Vector3(0,yaw,0)
	velocity = Vector3.ZERO
	speed = 0.0
	steering = 0.0
	for pivot in front_pivots: pivot.rotation.y = 0.0
	if is_instance_valid(lights): lights.set_driver_state(false,false)
	force_update_transform()
	get_global_transform_interpolated()
	reset_physics_interpolation()
	interpolation_reset_tick = Engine.get_physics_frames()

func _physics_process(delta: float) -> void:
	var throttle := Input.get_action_strength("accelerate") if enabled else 0.0
	var brake := Input.get_action_strength("reverse") if enabled else 0.0
	var handbrake := enabled and Input.is_action_pressed("handbrake")
	var steer_input := Input.get_axis("steer_left", "steer_right") if enabled else 0.0
	var brake_lights:bool=enabled and (handbrake or (brake>.05 and speed>=-.2) or (throttle>.05 and speed<-.2))
	lights.set_driver_state(brake_lights,enabled and speed<-.25)
	var offroad := is_offroad()
	var limit := 12.0 if offroad else MAX_SPEED
	if throttle > 0:
		speed = move_toward(speed, limit, (BRAKING if speed < 0 else ACCELERATION) * throttle * delta)
	elif brake > 0:
		speed = move_toward(speed, -REVERSE_SPEED, (BRAKING if speed > 0 else 5.0) * brake * delta)
	else:
		speed = move_toward(speed, 0.0, (4.5 if offroad else 1.8) * delta)
	if handbrake or not enabled:
		speed = move_toward(speed, 0.0, BRAKING * delta)
	if offroad and speed > limit:
		speed = move_toward(speed, limit, 14.0 * delta)
	steering = move_toward(steering, steer_input, delta * 4.0)
	# Reduce sensitivity at speed while preserving reverse steering.
	var angle := steering * STEERING_ANGLE / (1.0 + absf(speed) * 0.045)
	if enabled and is_on_floor():
		rotate_y(-speed / 2.7 * tan(angle) * delta)
	var forward := -global_transform.basis.z
	velocity.x = forward.x * speed
	velocity.z = forward.z * speed
	velocity.y = -2.0 if is_on_floor() else velocity.y - 22.0 * delta
	move_and_slide()
	if is_on_wall(): speed *= 0.72
	for pivot in front_pivots: pivot.rotation.y = -angle
	for wheel in wheels: wheel.rotate_x(-speed / wheel_radius * delta)
	if visual:
		visual.rotation.z = lerpf(visual.rotation.z, -steering * clampf(speed / MAX_SPEED, -1, 1) * 0.035, delta * 5)

func get_camera_target_transform() -> Transform3D:
	# The engine caches the client-side pose per physics tick. After a teleport,
	# follow the reset render pose until both cached snapshots reach the new location.
	if Engine.get_physics_frames() <= interpolation_reset_tick + 1:
		return global_transform
	return get_global_transform_interpolated()

func is_offroad() -> bool:
	if road_grid_spacing<=0: return absf(global_position.x)>4.2
	var x := absf(global_position.x-roundf(global_position.x/road_grid_spacing)*road_grid_spacing)
	var z := absf(global_position.z-roundf(global_position.z/road_grid_spacing)*road_grid_spacing)
	return minf(x,z)>7.0


func configure_environment(city:bool,night:bool=false) -> void:
	var glass:ShaderMaterial
	if city:
		glass=ShaderMaterial.new()
		glass.shader=load("res://materials/city_car_glass.gdshader")
		var prefix:="city_night_reflection_" if night and ResourceLoader.exists("res://textures/city_night_reflection_north.png") else "city_reflection_"
		glass.set_shader_parameter("reflection_north",load("res://textures/"+prefix+"north.png"))
		glass.set_shader_parameter("reflection_south",load("res://textures/"+prefix+"south.png"))
		glass.set_shader_parameter("reflection_exposure",.06 if night and prefix=="city_reflection_" else 1.0)
	if is_instance_valid(lights):lights.evaluate_darkness(0,true)
	for ob in visual.find_children("*","MeshInstance3D",true,false):
		ob.layers=3 if night else 1
		for index in ob.mesh.get_surface_count():
			var original:=ob.mesh.surface_get_material(index) as StandardMaterial3D
			if not original:continue
			var label:=original.resource_name.to_lower()
			if "glass" in label or "окна" in label:
				ob.set_surface_override_material(index,glass)
			elif "petrol" in label or "эмаль" in label:
				var paint:=original.duplicate() as StandardMaterial3D
				paint.clearcoat_enabled=true
				paint.clearcoat=.35
				paint.clearcoat_roughness=.2
				ob.set_surface_override_material(index,paint)
