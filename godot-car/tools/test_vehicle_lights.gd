extends SceneTree
var failed:=false
func check(ok:bool,text:String):
    print("PASS " if ok else "FAIL ",text)
    if not ok:failed=true
func _initialize():call_deferred("run")
func tick():
    for i in 3:await physics_frame
func run():
    var path:="user://lights_test_%d.cfg"%Time.get_ticks_usec()
    var config:=ConfigFile.new()
    config.set_value("race_tourer","best_time",11.0)
    config.set_value("race_city_tour_v2_tourer","best_time",17.0)
    config.set_value("race_city_night_tour_v2_tourer","best_time",23.0)
    config.set_value("garage","map","city")
    config.save(path)
    var game=load("res://game.tscn").instantiate()
    game.profile_path=path
    game.save_records=false
    game.selected_map="city"
    root.add_child(game)
    current_scene=game
    var day_environment:Environment=game.get_node("World/WorldEnvironment").environment
    var day_energy:float=day_environment.ambient_light_energy
    check(game.map_night_button!=null and game.selected_map=="city","third map button is available in garage")
    for vehicle in ["classic","tourer"]:
        game.select_vehicle(vehicle)
        var car=game.car
        var lights=car.lights
        lights.set_process(false)
        check(lights.headlamps.size()==2 and lights.lens_materials.size()>=2,"both "+vehicle+" headlamps and actual lens materials are connected")
        check(lights.headlamps[0].position.z< -1.5 and lights.rear_positions[0].z>1.5,"light sources align with the front and rear of "+vehicle)
        check(not lights.headlights_on,"automatic headlights stay off in daylight")
        car.enabled=true
        car.speed=10
        Input.action_press("reverse")
        await tick()
        check(lights.braking and float(lights.lens_materials[0].get_shader_parameter("brake_energy"))>3,"braking from forward motion lights the stop lenses")
        Input.action_release("reverse")
        await tick()
        check(not lights.braking,"releasing brake turns stop lights off")
        Input.action_press("handbrake")
        await tick()
        check(lights.braking,"handbrake lights stop signals")
        Input.action_release("handbrake")
        car.speed=-3
        Input.action_press("accelerate")
        await tick()
        check(lights.braking,"opposite pedal while reversing also counts as braking")
        Input.action_release("accelerate")
        car.speed=-3
        Input.action_press("reverse")
        await tick()
        check(not lights.braking and lights.reversing and lights.reverse_lamps[0].visible,"reverse acceleration uses white backup lamps, without false braking")
        Input.action_release("reverse")
        car.enabled=false
        car.reset_at(game.map_start())
        check(not lights.braking and not lights.reversing,"reset clears brake and reverse lamps")
        var sun:DirectionalLight3D=game.get_node("World/Sun")
        var original_sun:=sun.light_energy
        sun.light_energy=0
        day_environment.ambient_light_energy=.05
        lights.evaluate_darkness(.3)
        check(not lights.headlights_on,"short dark transition is debounced")
        lights.evaluate_darkness(.5)
        check(lights.headlights_on and lights.headlamps[0].visible,"sustained darkness switches real headlights on automatically")
        day_environment.ambient_light_energy=.35
        lights.evaluate_darkness(2)
        check(lights.headlights_on,"light sensor hysteresis avoids threshold flicker")
        day_environment.ambient_light_energy=day_energy
        sun.light_energy=original_sun
        lights.evaluate_darkness(.8)
        check(not lights.headlights_on,"headlights switch back off in sustained daylight")
    game.map_night_button.pressed.emit()
    check(game.selected_map=="city_night" and game.is_city_map() and game.car.road_grid_spacing==160,"night button loads urban physics and the full city route")
    check(game.gate_nodes.size()==13 and game.mini_map.visible,"night course has 12 checkpoints, finish and minimap")
    check(game.get_node("World").night_mode and game.get_node("World/NightLighting").positions.size()>300,"night scene has street lighting")
    check(game.car.lights.headlights_on,"night map starts with AUTO low beams on")
    check(game.best_time==23.0 and game.record_section()=="race_city_night_tour_v2_tourer","night map has an independent record")
    var night_environment:Environment=game.get_node("World/WorldEnvironment").environment
    check(night_environment!=day_environment and is_equal_approx(day_environment.ambient_light_energy,day_energy),"night lighting does not mutate the daytime environment")
    for vehicle in ["classic","tourer","classic","tourer"]:
        game.select_vehicle(vehicle)
        check(game.car.lights.headlights_on and game.car.get_child_count()==2 and game.car.visual.find_children("VehicleLights","Node3D",true,false).size()==1,"swapping models retains one light rig with AUTO on")
    game.select_map("desert")
    check(not game.car.lights.headlights_on and game.best_time==11.0,"desert restores daylight lights and its own record")
    game.select_map("city")
    check(not game.car.lights.headlights_on and game.best_time==17.0,"day city restores its lighting and record")
    game.select_map("city_night")
    game.save_records=true
    game.start_race()
    game.elapsed=22.0
    game.finish_race()
    config.load(path)
    check(config.get_value("race_city_night_tour_v2_tourer","best_time")==22.0 and config.get_value("race_city_tour_v2_tourer","best_time")==17.0 and config.get_value("race_tourer","best_time")==11.0,"saving night results preserves other maps")
    check(config.get_value("garage","map")=="city_night","selected night map persists")
    game.queue_free()
    await process_frame
    var restored=load("res://game.tscn").instantiate()
    restored.profile_path=path
    restored.save_records=false
    root.add_child(restored)
    current_scene=restored
    check(restored.selected_map=="city_night" and restored.car.lights.headlights_on,"saved night map and automatic lights restore at launch")
    restored.queue_free()
    await process_frame
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    print("VEHICLE_LIGHT_TESTS_DONE")
    quit(1 if failed else 0)
