extends Node3D

const CityBounds = preload("res://scripts/city_world.gd")
const PalmBayBounds = preload("res://scripts/palm_bay_world.gd")
const CarController = preload("res://scripts/car_controller.gd")
const GATES: Array[float] = [-160.0, -360.0, -580.0, -800.0, -940.0]
const START := Vector3(2.05, 0.2, 30)
enum RaceState { SELECTING, COUNTDOWN, RACING, FINISHED }
@export var save_records := true
@export var profile_path := "user://desert_drive.cfg"
@export var skip_selection := false
@export_enum("classic", "tourer") var selected_vehicle := "tourer"
@export_enum("desert", "city", "city_night", "palm_bay") var selected_map := "desert"
# A right-hand lane tour of the waterfront, outer districts, parks and downtown.
const CITY_ROUTE: Array[Vector3] = [
	Vector3(2.5,0,420),Vector3(2.5,0,322.5),Vector3(482.5,0,322.5),
	Vector3(482.5,0,-482.5),Vector3(-482.5,0,-482.5),Vector3(-482.5,0,-157.5),
	Vector3(-162.5,0,-157.5),Vector3(-162.5,0,157.5),Vector3(-322.5,0,157.5),
	Vector3(-322.5,0,482.5),Vector3(322.5,0,482.5),Vector3(322.5,0,-322.5),
	Vector3(-2.5,0,-322.5),Vector3(-2.5,0,80)]
var city_route: Array[Vector3] = []
var city_gates: Array[Vector3] = []
var city_directions: Array[Vector3] = []
var previous_race_position := Vector3.ZERO
var route_guides: Node3D
var map_desert_button: Button
var map_city_button: Button
var map_night_button: Button
var map_palm_button: Button
var map_subtitle: Label
var race_title: Label
var mini_map: Control
var state := RaceState.SELECTING
var hud_root: Control
var garage_root: Control
var vehicle_title: Label
var vehicle_description: Label
var classic_button: Button
var tourer_button: Button
var collision_shape: BoxShape3D
var countdown := 3.0
var elapsed := 0.0
var next_gate := 0
var recoveries := 0
var best_time := 0.0
var last_z := START.z
var car: CharacterBody3D
var camera: Camera3D
var gate_nodes: Array[Node3D] = []
var speed_label: Label
var light_status_label:Label
var audio_director:Node
var sound_popup:PopupPanel
var mute_checkbox:CheckBox
var status_label: Label
var progress_label: Label
var message_label: Label
var center_label: Label
var result_panel: PanelContainer
var result_label: Label
var pause_panel: PanelContainer
var message_timer := 0.0
var camera_initialized := false

func _ready() -> void:
	if "--verify-export" in OS.get_cmdline_user_args():
		save_records=false
		profile_path="user://_export_self_test.cfg"
	process_mode = Node.PROCESS_MODE_ALWAYS
	bind_inputs()
	var config := ConfigFile.new()
	if not skip_selection and config.load(profile_path) == OK:
		selected_vehicle = str(config.get_value("garage","selected","tourer"))
		selected_map = str(config.get_value("garage","map","desert"))
	if selected_vehicle not in ["classic","tourer"]: selected_vehicle = "tourer"
	if selected_map not in ["desert","city","city_night","palm_bay"]: selected_map="desert"
	build_city_course()
	if is_route_map():
		var old_world := get_node("World")
		remove_child(old_world)
		old_world.queue_free()
		var city := load(map_scene(selected_map)).instantiate() as Node3D
		city.name="World"
		add_child(city)
	var world := get_node("World")
	var original := world.get_node_or_null("Car")
	if original:
		world.remove_child(original)
		original.queue_free()
	car = CarController.new()
	car.name = "PlayerCar"
	world.add_child(car)
	var collision := CollisionShape3D.new()
	collision_shape = BoxShape3D.new()
	collision.shape = collision_shape
	collision.position.y = .53
	car.add_child(collision)
	install_vehicle(selected_vehicle)
	car.road_grid_spacing = 160.0 if is_route_map() else 0.0
	car.reset_at(map_start())
	camera = world.get_node("Camera3D")
	camera.current = true
	# Updated every rendered frame from an interpolated target, not interpolated twice.
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	create_gates()
	create_hud()
	create_garage()
	audio_director=Node.new()
	audio_director.set_script(load("res://scripts/game_audio.gd"))
	add_child(audio_director)
	audio_director.setup(self)
	create_sound_panel()
	if skip_selection: start_race()
	else: hud_root.hide()
	update_camera(1.0)
	if "--verify-export" in OS.get_cmdline_user_args():
		var verification:=Node.new()
		verification.set_script(load("res://scripts/export_self_test.gd"))
		add_child(verification)
		verification.call_deferred("run",self)

func bind_inputs() -> void:
	var bindings := {
		"accelerate": [KEY_W, KEY_UP], "reverse": [KEY_S, KEY_DOWN],
		"steer_left": [KEY_A, KEY_LEFT], "steer_right": [KEY_D, KEY_RIGHT],
		"handbrake": [KEY_SPACE], "recover": [KEY_R],
		"pause_game": [KEY_ESCAPE], "restart_race": [KEY_ENTER],
		"map_desert": [KEY_Q], "map_city": [KEY_E], "map_night": [KEY_N], "map_palm": [KEY_P], "horn": [KEY_H], "mute_audio": [KEY_M]
	}
	for action in bindings:
		if not InputMap.has_action(action): InputMap.add_action(action)
		for key in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			if not InputMap.action_has_event(action, event): InputMap.action_add_event(action, event)

func make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	return mat

func gate_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var ob := MeshInstance3D.new()
	ob.mesh = mesh
	ob.material_override = mat
	ob.position = pos
	parent.add_child(ob)

func create_gates() -> void:
	var orange := make_material(Color(.94,.43,.40) if selected_map=="palm_bay" else Color(.97,.42,.08))
	var white := make_material(Color(.92,.9,.78))
	var dark := make_material(Color(.04,.26,.38) if selected_map=="palm_bay" else Color(.055,.08,.09))
	for previous in gate_nodes:
		remove_child(previous)
		previous.queue_free()
	gate_nodes.clear()
	if is_instance_valid(route_guides):
		remove_child(route_guides)
		route_guides.queue_free()
		route_guides=null
	var half_width := 7.8 if selected_map=="palm_bay" else 7.2 if is_route_map() else 5.0
	for i in gate_count():
		var gate := Node3D.new()
		gate.name = "Checkpoint%d" % (i+1)
		gate.position = gate_position(i)
		var direction := gate_direction(i)
		gate.rotation.y = atan2(-direction.x,-direction.z)
		add_child(gate)
		gate_nodes.append(gate)
		for x in [-half_width,half_width]:
			gate_box(gate,Vector3(x,2.8,0),Vector3(.25,5.6,.25),orange)
			gate_box(gate,Vector3(x,.15,0),Vector3(.85,.3,.85),dark)
		gate_box(gate,Vector3(0,5.6,0),Vector3(half_width*2+.3,.7,.16),dark)
		if i == gate_count()-1:
			var span:=half_width*2+.3
			var columns:=roundi(span/.5)
			var cell:=span/columns
			for j in columns:
				var x:=-span*.5+(j+.5)*cell
				gate_box(gate,Vector3(x,5.43,.12),Vector3(cell,.32,.06),white if j%2==0 else dark)
				gate_box(gate,Vector3(x,5.77,.12),Vector3(cell,.32,.06),dark if j%2==0 else white)
		var text := Label3D.new()
		text.text = "FINISH" if i==gate_count()-1 else "CHECKPOINT  %d / %d"%[i+1,gate_count()-1]
		text.position = Vector3(0,6.5,0)
		text.font_size = 80
		text.pixel_size = .012
		text.outline_size = 8
		gate.add_child(text)
	if is_route_map(): create_route_guides()

func label(text: String, size: int, color := Color(.94,.92,.84)) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.add_theme_color_override("font_shadow_color",Color(0,0,0,.85))
	node.add_theme_constant_override("shadow_offset_x",2)
	node.add_theme_constant_override("shadow_offset_y",2)
	return node

func panel(parent: Node, pos: Vector2, size: Vector2) -> PanelContainer:
	var node := PanelContainer.new()
	node.position = pos
	node.custom_minimum_size = size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.025,.045,.055,.88)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	node.add_theme_stylebox_override("panel",style)
	parent.add_child(node)
	return node

func button(text: String, callback: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size = Vector2(0,44)
	node.add_theme_font_size_override("font_size",20)
	node.pressed.connect(callback)
	return node

func create_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var canvas := Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(canvas)
	hud_root = canvas
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var top := panel(canvas,Vector2(24,24),Vector2(410,130))
	var box := VBoxContainer.new()
	top.add_child(box)
	race_title = label(map_race_title(),26,Color(1,.7,.32))
	box.add_child(race_title)
	status_label = label("",22)
	progress_label = label("",18)
	box.add_child(status_label)
	box.add_child(progress_label)
	speed_label = label("0 км/ч",44)
	canvas.add_child(speed_label)
	speed_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	speed_label.offset_left = -245
	speed_label.offset_top = -92
	speed_label.offset_right = -20
	speed_label.offset_bottom = -20
	light_status_label=label("",16,Color(.62,.9,.73))
	canvas.add_child(light_status_label)
	light_status_label.position=Vector2(26,146)
	var help := label("W / ↑ — газ    S / ↓ — тормоз, задний ход\nA D / ← → — руль    Пробел — ручник\nR — на дорогу (+5 с)    H — сигнал    M — звук    Esc — пауза",17)
	canvas.add_child(help)
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.offset_left = 24
	help.offset_top = -103
	help.offset_right = 720
	help.offset_bottom = -20
	message_label = label("",22,Color(1,.77,.36))
	canvas.add_child(message_label)
	message_label.position = Vector2(24,177)
	center_label = label("",72)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	canvas.add_child(center_label)
	center_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center_label.offset_left = -350
	center_label.offset_top = -95
	center_label.offset_right = 350
	center_label.offset_bottom = 95
	result_panel = panel(canvas,Vector2(300,245),Vector2(500,275))
	var result_box := VBoxContainer.new()
	result_box.add_theme_constant_override("separation",14)
	result_panel.add_child(result_box)
	result_label = label("",25)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_box.add_child(result_label)
	result_box.add_child(button("В гараж  ·  Enter",restart))
	result_panel.hide()
	pause_panel = panel(canvas,Vector2(350,280),Vector2(400,220))
	var pause_box := VBoxContainer.new()
	pause_box.add_theme_constant_override("separation",14)
	pause_panel.add_child(pause_box)
	pause_box.add_child(label("ПАУЗА",32))
	pause_box.add_child(button("Продолжить  ·  Esc",toggle_pause))
	pause_box.add_child(button("Звук",show_sound_panel))
	pause_box.add_child(button("В гараж",restart))
	pause_panel.hide()
	mini_map = Control.new()
	mini_map.set_script(load("res://scripts/route_map.gd"))
	mini_map.game = self
	canvas.add_child(mini_map)
	mini_map.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	mini_map.offset_left=-244
	mini_map.offset_top=24
	mini_map.offset_right=-24
	mini_map.offset_bottom=244
	mini_map.mouse_filter=Control.MOUSE_FILTER_IGNORE
	mini_map.visible=is_route_map()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mute_audio") and not event.is_echo():
		audio_director.set_muted(not audio_director.muted)
		mute_checkbox.set_pressed_no_signal(audio_director.muted)
		return
	if event.is_action_pressed("horn") and not event.is_echo():
		audio_director.honk()
		return
	if state == RaceState.SELECTING:
		if event.is_action_pressed("restart_race"): start_race()
		elif event.is_action_pressed("steer_left"): select_vehicle("classic")
		elif event.is_action_pressed("steer_right"): select_vehicle("tourer")
		elif event.is_action_pressed("map_desert"): select_map("desert")
		elif event.is_action_pressed("map_city"): select_map("city")
		elif event.is_action_pressed("map_night"): select_map("city_night")
		elif event.is_action_pressed("map_palm"): select_map("palm_bay")
		return
	if event.is_action_pressed("pause_game") and not event.is_echo():
		toggle_pause()
	elif event.is_action_pressed("restart_race") and state == RaceState.FINISHED:
		restart()
	elif event.is_action_pressed("recover") and not get_tree().paused and state == RaceState.RACING:
		recover()

func toggle_pause() -> void:
	if state in [RaceState.SELECTING,RaceState.FINISHED]: return
	get_tree().paused = not get_tree().paused
	pause_panel.visible = get_tree().paused

func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func recover() -> void:
	var pos := map_start()
	var yaw := 0.0
	if next_gate>0:
		var direction := gate_direction(next_gate-1)
		var right := direction.cross(Vector3.UP)
		pos = gate_position(next_gate-1)+direction*9.0+right*(2.5 if is_route_map() else 2.05)
		pos.y=.2
		yaw=atan2(-direction.x,-direction.z)
	car.reset_at(pos,yaw)
	previous_race_position=pos
	last_z=pos.z
	elapsed+=5.0
	recoveries+=1
	camera_initialized=false
	message("Возврат на дорогу: +5 секунд")

func message(text: String) -> void:
	message_label.text = text
	message_timer = 3.0

func _process(delta: float) -> void:
	if not is_instance_valid(car): return
	if not get_tree().paused:
		update_camera(delta)
		message_timer = maxf(0,message_timer-delta)
		if message_timer == 0: message_label.text = ""
		if state == RaceState.COUNTDOWN:
			countdown -= delta
			center_label.text = str(ceili(countdown)) if countdown>0 else ""
			if countdown<=0:
				state = RaceState.RACING
				car.enabled = true
				message("СТАРТ! Следуй голубым стрелкам и карте" if is_route_map() else "СТАРТ! Пройди 4 точки и доберись до финиша")
		elif state == RaceState.RACING:
			elapsed += delta
			var outside := route_outside_bounds(car.position) if is_route_map() else absf(car.position.x)>140 or car.position.z>95 or car.position.z < -995
			if car.position.y < -8 or outside: recover()
		elif state == RaceState.FINISHED:
			center_label.text = ""
	light_status_label.text="Ближний свет  AUTO · ВКЛ" if car.lights.headlights_on else "Свет  AUTO"
	if audio_director.muted:light_status_label.text+="  ·  Звук выкл"
	speed_label.text = "%03d км/ч" % roundi(absf(car.speed)*3.6)
	status_label.text = "Время  %s" % format_time(elapsed)
	var distance := car.position.distance_to(gate_position(mini(next_gate,gate_count()-1))) if is_route_map() else maxf(0,car.position.z-GATES[mini(next_gate,GATES.size()-1)])
	var target := "Финиш" if next_gate >= gate_count()-1 else "Точка %d / %d"%[next_gate+1,gate_count()-1]
	progress_label.text = "%s  ·  %d м%s"%[target,roundi(distance),("  ·  ТРОТУАР" if is_route_map() else "  ·  ГРУНТ") if car.is_offroad() else ""]

	if is_route_map() and state==RaceState.RACING and route_near_boundary(car.position) and message_timer<=0:
		message_label.text="Край игровой зоны — впереди возврат к последней точке"

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(car) or get_tree().paused: return
	if is_route_map():
		check_city_gate()
		previous_race_position=car.position
		return
	if state == RaceState.RACING and next_gate < GATES.size():
		var z := GATES[next_gate]
		if last_z > z and car.position.z <= z:
			# Plane intersection checks the complete motion segment, avoiding missed gates at high speed.
			var t := (last_z-z)/maxf(.0001,last_z-car.position.z)
			var previous_x := car.position.x-car.get_position_delta().x
			var cross_x := lerpf(previous_x,car.position.x,t)
			if absf(cross_x)<4.65 and car.position.y < 3.0:
				gate_nodes[next_gate].visible = false
				next_gate += 1
				if next_gate == GATES.size(): finish_race()
				else: message("Контрольная точка %d / 4 пройдена"%next_gate)
			else:
				message("Точка пропущена! Вернись к ней или нажми R")
	last_z = car.position.z

func finish_race() -> void:
	state = RaceState.FINISHED
	car.enabled = false
	var new_best := best_time <= 0 or elapsed < best_time
	if new_best:
		best_time = elapsed
		var config := ConfigFile.new()
		config.load(profile_path)
		config.set_value(record_section(),"best_time",best_time)
		if save_records: config.save(profile_path)
	result_label.text = "ФИНИШ!\nТвоё время: %s\nРекорд: %s%s\nВозвратов на дорогу: %d"%[format_time(elapsed),format_time(best_time),"  ★" if new_best else "",recoveries]
	result_panel.show()
	message_label.text = ""

func format_time(seconds: float) -> String:
	var hundredths := int(seconds*100)
	return "%02d:%02d.%02d"%[hundredths/6000,(hundredths/100)%60,hundredths%100]

func update_camera(delta: float) -> void:
	# Use the same interpolated pose that Godot renders for the car and its wheels.
	# Reading global_position here produces visible steps between 60 Hz physics ticks.
	var target: Transform3D = car.get_camera_target_transform()
	if state == RaceState.SELECTING:
		camera.fov = 50
		camera.global_position = target.origin+Vector3(5.8,2.9,-6.6)
		camera.look_at(target.origin+Vector3(0,.32,0))
		return
	camera.fov = 68
	var desired := target.origin + target.basis * Vector3(0,3.6,8.8)
	if not camera_initialized:
		camera.global_position = desired
		camera_initialized = true
	else:
		camera.global_position = camera.global_position.lerp(desired,1.0-exp(-delta*6.0))
	camera.look_at(target.origin + Vector3(0,1.3,0) - target.basis.z*7.0)


func install_vehicle(id: String) -> void:
	if is_instance_valid(car.visual):
		var previous: Node3D = car.visual
		car.remove_child(previous)
		previous.queue_free()
	var path := "res://assets/car.glb" if id=="classic" else "res://assets/grand_tourer.glb"
	var model := load(path).instantiate() as Node3D
	car.add_child(model)
	model.transform = Transform3D.IDENTITY
	car.setup(model)
	car.configure_environment(is_city_map(),selected_map=="city_night")
	car.wheel_radius = .48 if id=="classic" else .445
	collision_shape.size = Vector3(1.8,1.05,4.25) if id=="classic" else Vector3(1.92,1.05,4.64)
	load_best_time()

func select_vehicle(id: String) -> void:
	if state != RaceState.SELECTING: return
	if id != selected_vehicle:
		selected_vehicle = id
		install_vehicle(id)
	update_garage()

func update_garage() -> void:
	vehicle_title.text = "CLASSIC  /  01" if selected_vehicle=="classic" else "GRAND TOURER  /  02"
	vehicle_description.text = ("Красный оригинал. Простые формы и знакомый силуэт." if selected_vehicle=="classic" else "Купе: металлическая краска, литые диски, детальные фары и кузов.")
	vehicle_description.text += "\nРекорд: " + (format_time(best_time) if best_time>0 else "первый заезд впереди")
	classic_button.text = ("●  " if selected_vehicle=="classic" else "○  ")+"Classic"
	tourer_button.text = ("●  " if selected_vehicle=="tourer" else "○  ")+"Grand Tourer"
	map_subtitle.text = ("Pacific City · ночь · фары AUTO · %.1f км" if selected_map=="city_night" else "Pacific City · %.1f км · парки, набережная, центр")%(city_course_length()/1000.0) if is_route_map() else "Невада · пустынное шоссе · заезд на время"
	map_desert_button.text = ("●  " if selected_map=="desert" else "○  ")+"Пустыня"
	map_city_button.text = ("●  " if selected_map=="city" else "○  ")+"Город"
	map_night_button.text = ("●  " if selected_map=="city_night" else "○  ")+"Ночной город"
	map_palm_button.text = ("●  " if selected_map=="palm_bay" else "○  ")+"Palm Bay"
	if selected_map=="palm_bay":map_subtitle.text="Palm Bay · вечное лето · %.1f км · море, пальмы и бассейны"%(city_course_length()/1000.0)

func start_race() -> void:
	if state != RaceState.SELECTING: return
	state = RaceState.COUNTDOWN
	countdown = 3.0
	car.reset_at(map_start())
	previous_race_position=car.position
	car.enabled = false
	last_z = map_start().z
	camera_initialized = false
	if is_instance_valid(garage_root): garage_root.hide()
	hud_root.show()
	if save_records:
		var config := ConfigFile.new()
		config.load(profile_path)
		config.set_value("garage","selected",selected_vehicle)
		config.set_value("garage","map",selected_map)
		config.save(profile_path)

func create_garage() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	garage_root = Control.new()
	layer.add_child(garage_root)
	garage_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	garage_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var header := panel(garage_root,Vector2(24,24),Vector2(1052,180))
	var header_box := VBoxContainer.new()
	header.add_child(header_box)
	var game_title:=str(ProjectSettings.get_setting("application/config/name")).to_upper()
	header_box.add_child(label(game_title+"  /  ГАРАЖ",30,Color(1,.72,.37)))
	map_subtitle=label("",18)
	header_box.add_child(map_subtitle)
	var maps := HBoxContainer.new()
	maps.add_theme_constant_override("separation",12)
	header_box.add_child(maps)
	map_desert_button=button("Пустыня",func(): select_map("desert"))
	map_city_button=button("Город",func(): select_map("city"))
	map_night_button=button("Ночной город",func(): select_map("city_night"))
	map_palm_button=button("Palm Bay",func(): select_map("palm_bay"))
	for option in [map_desert_button,map_city_button,map_night_button,map_palm_button]:
		option.focus_mode=Control.FOCUS_NONE
		option.custom_minimum_size=Vector2(235,42)
		maps.add_child(option)
	var card := panel(garage_root,Vector2(24,550),Vector2(1052,226))
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation",8)
	card.add_child(content)
	vehicle_title = label("",27,Color(1,.72,.37))
	content.add_child(vehicle_title)
	vehicle_description = label("",18)
	content.add_child(vehicle_description)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",14)
	content.add_child(row)
	classic_button = button("Classic",func(): select_vehicle("classic"))
	tourer_button = button("Grand Tourer",func(): select_vehicle("tourer"))
	for option in [classic_button,tourer_button]:
		option.custom_minimum_size = Vector2(235,46)
		option.focus_mode = Control.FOCUS_NONE
		row.add_child(option)
	var start_button := button("На старт  →  Enter",start_race)
	start_button.custom_minimum_size = Vector2(310,46)
	start_button.focus_mode = Control.FOCUS_NONE
	row.add_child(start_button)
	row.add_child(button("Звук",show_sound_panel))
	content.add_child(label("Q / E / N / P — карта     ← → — машина     Enter — начать заезд",16,Color(.7,.76,.75)))
	update_garage()


func show_sound_panel() -> void:
	mute_checkbox.set_pressed_no_signal(audio_director.muted)
	sound_popup.popup_centered(Vector2i(560,470))

func create_sound_panel() -> void:
	sound_popup=PopupPanel.new()
	sound_popup.name="SoundSettings"
	sound_popup.process_mode=Node.PROCESS_MODE_ALWAYS
	var panel_style:=StyleBoxFlat.new()
	panel_style.bg_color=Color(.035,.045,.05,.98)
	panel_style.set_corner_radius_all(12)
	panel_style.set_border_width_all(1)
	panel_style.border_color=Color(.3,.34,.35)
	sound_popup.add_theme_stylebox_override("panel",panel_style)
	add_child(sound_popup)
	var margin:=MarginContainer.new()
	for side in ["left","top","right","bottom"]:margin.add_theme_constant_override("margin_"+side,18)
	sound_popup.add_child(margin)
	var content:=VBoxContainer.new()
	content.add_theme_constant_override("separation",12)
	margin.add_child(content)
	content.add_child(label("ЗВУК",26))
	mute_checkbox=CheckBox.new()
	mute_checkbox.text="Без звука  ·  M"
	mute_checkbox.button_pressed=audio_director.muted
	mute_checkbox.toggled.connect(func(value:bool):audio_director.set_muted(value))
	content.add_child(mute_checkbox)
	for category in ["master","vehicle","ambience"]:
		content.add_child(label({"master":"Общая громкость","vehicle":"Машина и шины","ambience":"Город и море"}[category],18))
		var slider:=HSlider.new()
		slider.min_value=0;slider.max_value=1;slider.step=.01
		slider.value=audio_director.levels[category]
		slider.value_changed.connect(func(value:float):audio_director.set_volume(category,value))
		content.add_child(slider)
	var credits:=RichTextLabel.new()
	credits.bbcode_enabled=true
	credits.custom_minimum_size=Vector2(510,100)
	credits.text="Двигатель: lonemonk — [url=https://freesound.org/people/lonemonk/sounds/240671/]Chrysler Start and Idle (Exhaust perspective)[/url], [url=https://creativecommons.org/licenses/by/4.0/]CC BY 4.0[/url]. Нарезка, эквализация, зацикливание, изменение тона.\nСигнал и ручник: GGBotNet · город: IgnasD · прибой: jasinski (CC0).\nШины: audible-edge / Tom Haigh, через qubodup — [url=https://opengameart.org/content/car-tire-squeal-skid-loop]Car tire squeal skid loop[/url], [url=https://creativecommons.org/licenses/by/3.0/]CC BY 3.0[/url]. Фильтрация, нормализация, зацикливание."
	credits.meta_clicked.connect(func(url:Variant):OS.shell_open(str(url)))
	content.add_child(credits)
	content.add_child(button("Готово",func():sound_popup.hide();audio_director.save_settings()))

func build_city_course() -> void:
	city_route.assign(PalmBayBounds.ROUTE if selected_map=="palm_bay" else CITY_ROUTE)
	city_gates.clear()
	city_directions.clear()
	for i in range(city_route.size()-1):
		var segment:Vector3=city_route[i+1]-city_route[i]
		var direction:=Vector3(signf(segment.x),0,0) if absf(segment.x)>absf(segment.z) else Vector3(0,0,signf(segment.z))
		var lane_point:=city_route[i+1] if i==city_route.size()-2 else city_route[i].lerp(city_route[i+1],.65)
		var center:=lane_point
		if absf(direction.x)>.5:center.z=roundf(center.z/160)*160
		else:center.x=roundf(center.x/160)*160
		city_gates.append(center)
		city_directions.append(direction)

func gate_count() -> int:
	return city_gates.size() if is_route_map() else GATES.size()

func city_course_length() -> float:
	var length:=0.0
	for i in range(city_route.size()-1):length+=city_route[i].distance_to(city_route[i+1])
	return length

func is_route_map(id:String="") -> bool:
	return (selected_map if id.is_empty() else id) in ["city","city_night","palm_bay"]

func is_city_map(id:String="") -> bool:
	return (selected_map if id.is_empty() else id) in ["city","city_night"]

func route_outside_bounds(pos:Vector3) -> bool:
	return PalmBayBounds.outside_play_area(pos) if selected_map=="palm_bay" else CityBounds.outside_play_area(pos)

func route_near_boundary(pos:Vector3) -> bool:
	return PalmBayBounds.near_boundary(pos) if selected_map=="palm_bay" else CityBounds.near_boundary(pos)

func map_scene(id:String) -> String:
	return {"desert":"res://nevada.tscn","city":"res://city.tscn","city_night":"res://city_night.tscn","palm_bay":"res://palm_bay.tscn"}[id]

func map_race_title() -> String:
	if selected_map=="palm_bay":return "PALM BAY / SUMMER DRIVE"
	if selected_map=="city_night":return "PACIFIC / NIGHT RUN"
	return "PACIFIC / CITY RUN" if is_route_map() else "NEVADA / DESERT RUN"

func map_start() -> Vector3:
	if selected_map=="palm_bay":return PalmBayBounds.START
	return Vector3(2.5,.2,420) if is_route_map() else START

func gate_position(i: int) -> Vector3:
	return city_gates[i] if is_route_map() else Vector3(0,0,GATES[i])

func gate_direction(i: int) -> Vector3:
	return city_directions[i] if is_route_map() else Vector3.FORWARD

func record_section() -> String:
	if selected_map=="palm_bay":return "race_palm_bay_v1_"+selected_vehicle
	if selected_map=="city_night":return "race_city_night_tour_v2_"+selected_vehicle
	return "race_city_tour_v2_"+selected_vehicle if is_route_map() else "race_"+selected_vehicle

func load_best_time() -> void:
	var config := ConfigFile.new()
	best_time=0.0
	if config.load(profile_path)==OK:
		var fallback: Variant = config.get_value("race","best_time",0.0) if selected_map=="desert" and selected_vehicle=="classic" else 0.0
		best_time=float(config.get_value(record_section(),"best_time",fallback))

func select_map(id: String) -> void:
	if state!=RaceState.SELECTING or id==selected_map or id not in ["desert","city","city_night","palm_bay"]: return
	selected_map=id
	build_city_course()
	car.reparent(self)
	var previous := get_node("World")
	remove_child(previous)
	previous.queue_free()
	var world := load(map_scene(id)).instantiate() as Node3D
	world.name="World"
	add_child(world)
	var original := world.get_node_or_null("Car")
	if original:
		world.remove_child(original)
		original.queue_free()
	car.reparent(world,false)
	car.road_grid_spacing=160 if is_route_map(id) else 0
	car.configure_environment(is_city_map(id),id=="city_night")
	car.reset_at(map_start())
	previous_race_position=car.position
	last_z=car.position.z
	camera=world.get_node("Camera3D")
	camera.current=true
	camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera_initialized=false
	create_gates()
	load_best_time()
	mini_map.visible=is_route_map(id)
	race_title.text=map_race_title()
	update_garage()
	update_camera(1.0)

func check_city_gate() -> void:
	if state!=RaceState.RACING or next_gate>=city_gates.size(): return
	var target:=city_gates[next_gate]
	var direction:=city_directions[next_gate]
	var a:float=(previous_race_position-target).dot(direction)
	var b:float=(car.position-target).dot(direction)
	if a<0 and b>=0:
		var cross_pos:=previous_race_position.lerp(car.position,-a/maxf(.0001,b-a))
		if absf((cross_pos-target).dot(direction.cross(Vector3.UP)))<7.0 and cross_pos.y<3.0:
			gate_nodes[next_gate].hide()
			next_gate+=1
			if next_gate==city_gates.size(): finish_race()
			else: message("Точка %d / %d! Следуй маршруту на карте"%[next_gate,city_gates.size()-1])
		else: message("Точка пропущена — вернись к арке или нажми R")

func create_route_guides() -> void:
	route_guides=Node3D.new()
	route_guides.name="CityRouteGuides"
	add_child(route_guides)
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(city_route.size()-1):
		var a:=city_route[i]
		var b:=city_route[i+1]
		var direction:Vector3=(b-a).normalized()
		var right:=direction.cross(Vector3.UP)
		var count:=int(a.distance_to(b)/24.0)
		for j in range(1,count):
			var pos:=a+direction*j*24.0+Vector3(0,.075,0)
			surface.add_vertex(pos+direction*1.5)
			surface.add_vertex(pos-direction*.9+right*.65)
			surface.add_vertex(pos-direction*.9-right*.65)
	surface.generate_normals()
	var mesh:=MeshInstance3D.new()
	mesh.mesh=surface.commit()
	var material:=make_material(Color(.035,.65,.85))
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	material.emission_enabled=true
	material.emission=Color(.01,.18,.22)
	mesh.material_override=material
	route_guides.add_child(mesh)
