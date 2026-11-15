extends "res://tools/test_city.gd"
## Reuses the city test's rounded-path driver, with a separate resort course.
func run():
    var profile:="user://palm_bay_test_%d.cfg"%Time.get_ticks_usec()
    var vehicle:="tourer" if "tourer" in OS.get_cmdline_user_args() else "classic"
    var config:=ConfigFile.new()
    config.set_value("garage","selected",vehicle)
    config.set_value("garage","map","desert")
    config.set_value("race_"+vehicle,"best_time",12.0)
    config.set_value("race_city_tour_v2_"+vehicle,"best_time",19.0)
    config.set_value("race_palm_bay_v1_"+vehicle,"best_time",34.0)
    config.set_value("unrelated","keep",true)
    config.save(profile)
    var game=load("res://game.tscn").instantiate()
    game.profile_path=profile
    game.save_records=false
    root.add_child(game)
    current_scene=game
    game.map_palm_button.pressed.emit()
    check(game.selected_map=="palm_bay" and game.is_route_map() and not game.is_city_map(),"fourth map is available from its garage button")
    var world=game.get_node("World")
    check(world.get_node("ArtGeometry").scene_file_path.ends_with("palm_bay.glb"),"game loads the model exported from Blender")
    check(world.palm_count>=120 and world.building_count>=30 and world.pool_count>=30,"resort has detailed roadside villas and open pool terraces")
    check(world.get_node("PalmCollisions").get_child_count()>=30,"Blender collision proxies are loaded")
    check(game.gate_count()==9 and game.city_course_length()>3500 and game.mini_map.visible,"resort has its own 3.5 km route and minimap")
    var aligned:=true
    for i in game.city_gates.size():
        var pos:Vector3=game.city_gates[i]
        var direction:Vector3=game.city_directions[i]
        var across:float=pos.z if absf(direction.x)>.5 else pos.x
        if absf(across-roundf(across/160)*160)>.001:aligned=false
        if absf(direction.x)+absf(direction.z)<.999:aligned=false
    check(aligned,"checkpoint and finish arches are centered and perpendicular to the streets")
    check(game.best_time==34 and not game.car.is_offroad() and not game.car.lights.headlights_on,"record, road start and sunny automatic lights match the map")
    game.audio_director._process(8)
    check(float(game.audio_director.gains.ocean_waves)>.1 and float(game.audio_director.gains.city_traffic)<.06,"coastal ambience is present without loud city traffic")
    game.select_map("city")
    check(game.gate_count()==13 and game.city_course_length()>5500 and game.best_time==19,"switching back retains the original city route and record")
    game.select_map("palm_bay")
    check(game.gate_count()==9 and game.car.get_child_count()==2,"returning to resort restores its own route without duplicated cars")
    game.save_records=true
    game.start_race()
    game.countdown=.01
    for i in 30:await physics_frame
    var route:=rounded_route(game.city_route)
    var target_index:=1
    var wall_frames:=0
    for frame in 40000:
        var flat:Vector3=game.car.position
        flat.y=0
        while target_index<route.size()-1 and flat.distance_to(route[target_index])<4.5:target_index+=1
        var desired:Vector3=(route[target_index]-flat).normalized()
        var angle:float=(-game.car.global_basis.z).signed_angle_to(desired,Vector3.UP)
        var steer:float=clampf(-angle*2.4,-1,1)
        Input.action_press("steer_right",maxf(steer,0))
        Input.action_press("steer_left",maxf(-steer,0))
        if game.car.speed<8:
            Input.action_release("reverse")
            Input.action_press("accelerate")
        elif game.car.speed>8.6:
            Input.action_release("accelerate")
            Input.action_press("reverse",.3)
        else:
            Input.action_release("accelerate")
            Input.action_release("reverse")
        await physics_frame
        if game.car.is_on_wall():wall_frames+=1
        if game.state==game.RaceState.FINISHED:break
        if frame%7000==0:print("PALM_PROGRESS ",vehicle," frame=",frame," position=",game.car.position," gates=",game.next_gate)
    for action in ["accelerate","reverse","steer_left","steer_right"]:Input.action_release(action)
    check(game.state==game.RaceState.FINISHED and game.next_gate==9,"complete resort route with real driving physics on "+vehicle)
    check(game.recoveries==0 and wall_frames==0,"all turns and checkpoints clear the resort scenery")
    game.best_time=0
    game.elapsed=32
    game.save_records=true
    game.finish_race()
    config.load(profile)
    check(config.get_value("race_palm_bay_v1_"+vehicle,"best_time")==32 and config.get_value("race_city_tour_v2_"+vehicle,"best_time")==19 and config.get_value("race_"+vehicle,"best_time")==12 and config.get_value("unrelated","keep"),"resort records preserve other maps and user settings")
    game.state=game.RaceState.RACING
    game.next_gate=2
    game.recover()
    check((-game.car.global_basis.z).dot(game.gate_direction(1))>.99 and not game.route_outside_bounds(game.car.position),"recovery retains the completed street direction within resort bounds")
    game.queue_free()
    await process_frame
    var restored=load("res://game.tscn").instantiate()
    restored.profile_path=profile
    restored.save_records=false
    root.add_child(restored)
    current_scene=restored
    check(restored.selected_map=="palm_bay" and restored.gate_count()==9 and restored.best_time==32,"saved resort selection and course restore after relaunch")
    restored.queue_free()
    for i in 3:await process_frame
    DirAccess.remove_absolute(ProjectSettings.globalize_path(profile))
    print("PALM_BAY_TESTS_DONE ",vehicle)
    quit(1 if failed else 0)
