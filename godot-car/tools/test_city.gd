extends SceneTree
var failed := false
func check(ok: bool, description: String) -> void:
    print("PASS " if ok else "FAIL ",description)
    if not ok:failed=true
func _initialize():call_deferred("run")
func sample_line(points: Array[Vector3], a: Vector3, b: Vector3):
    var steps:=maxi(1,ceili(a.distance_to(b)/4))
    for i in range(1,steps+1):points.append(a.lerp(b,float(i)/steps))
func rounded_route(route: Array[Vector3]) -> Array[Vector3]:
    var result:Array[Vector3]=[route[0]]
    var current:=route[0]
    var radius:=12.0
    for i in range(1,route.size()-1):
        var incoming:Vector3=(route[i]-route[i-1]).normalized()
        var outgoing:Vector3=(route[i+1]-route[i]).normalized()
        var start:Vector3=route[i]-incoming*radius
        var end:Vector3=route[i]+outgoing*radius
        var center:Vector3=start+outgoing*radius
        sample_line(result,current,start)
        var angle:float=(start-center).signed_angle_to(end-center,Vector3.UP)
        for j in range(1,13):result.append(center+(start-center).rotated(Vector3.UP,angle*j/12.0))
        current=end
    sample_line(result,current,route[-1])
    return result
func run():
    var game=load("res://game.tscn").instantiate()
    var night:= "night" in OS.get_cmdline_user_args()
    var map_id:="city_night" if night else "city"
    var record_prefix:="race_city_night_tour_v2_" if night else "race_city_tour_v2_"
    var profile := "user://city_test_%d.cfg"%Time.get_ticks_usec()
    var seed_config := ConfigFile.new()
    var vehicle := "tourer" if "tourer" in OS.get_cmdline_user_args() else "classic"
    seed_config.set_value("garage","selected",vehicle)
    seed_config.set_value("race_"+vehicle,"best_time",12.0)
    seed_config.set_value("race_city_"+vehicle,"best_time",15.0)
    seed_config.set_value(record_prefix+vehicle,"best_time",34.0)
    seed_config.set_value("unrelated","keep",true)
    seed_config.save(profile)
    game.profile_path=profile
    game.save_records=false
    root.add_child(game)
    current_scene=game
    (game.map_night_button if night else game.map_city_button).pressed.emit()
    check(game.selected_map==map_id and game.car.road_grid_spacing==160,"city selected from map button")
    check(game.best_time==34.0,"city record loaded separately")
    check(game.get_node("World/CityCollisions").get_child_count()>=180,"Blender building and parked car colliders imported")
    check(game.get_node("World/CityModel").get_child_count()>0,"Blender city geometry loaded")
    check(not game.car.is_offroad(),"city start is a road, not desert offroad")
    var world=game.get_node("World")
    world.clock=0
    check(world.light_state(0)==2 and world.light_state(1)==0,"north/south green and crossing red")
    world.clock=15
    check(world.light_state(0)==1 and world.light_state(1)==0,"yellow transition")
    world.clock=17.5
    check(world.light_state(0)==0 and world.light_state(1)==0,"all red safety interval")
    world.clock=20
    check(world.light_state(0)==0 and world.light_state(1)==2,"east/west green and crossing red")
    game.map_desert_button.pressed.emit()
    check(game.selected_map=="desert" and game.car.road_grid_spacing==0,"desert can be restored")
    check(game.best_time==12.0,"desert record preserved when switching map")
    (game.map_night_button if night else game.map_city_button).pressed.emit()
    check(game.gate_nodes.size()==game.city_gates.size() and game.car.get_child_count()==2,"map swaps do not duplicate vehicle or checkpoints")
    check(game.city_course_length()>5500 and game.city_gates.size()==13,"long route visits both sides of the city with 12 checkpoints and a finish")
    game.start_race()
    game.countdown=.01
    for i in 30:await physics_frame
    # A genuine drive with steering and braking through rounded city corners.
    var route:=rounded_route(game.city_route)
    var target_index:=1
    var wall_frames:=0
    for frame in 65000:
        var flat:Vector3=game.car.position
        flat.y=0
        while target_index<route.size()-1 and flat.distance_to(route[target_index])<4.5:
            target_index+=1
        var desired:Vector3=(route[target_index]-flat).normalized()
        var forward:Vector3=-game.car.global_basis.z
        var angle:float=forward.signed_angle_to(desired,Vector3.UP)
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
        if frame%5000==0:print("CITY_PROGRESS frame=",frame," position=",game.car.position," gates=",game.next_gate)
    for action in ["accelerate","reverse","steer_left","steer_right"]:Input.action_release(action)
    check(game.state==game.RaceState.FINISHED and game.next_gate==game.city_gates.size(),"complete city course with real physics, steering, all turns and finish")
    check(game.recoveries==0,"city route needs no recovery or teleport")
    check(wall_frames==0,"entire route clears parked vehicles and street furniture")
    print("CITY_WALL_FRAMES ",wall_frames)
    game.best_time=0
    game.elapsed=32
    game.save_records=true
    game.finish_race()
    var config:=ConfigFile.new()
    config.load(profile)
    check(config.get_value("race_"+vehicle,"best_time")==12.0 and config.get_value(record_prefix+vehicle,"best_time")==32.0 and config.get_value("race_city_"+vehicle,"best_time")==15.0 and config.get_value("unrelated","keep")==true,"city record save preserves desert and profile settings")
    # Recovery after an eastbound checkpoint must preserve the correct heading.
    game.state=game.RaceState.RACING
    game.next_gate=2
    game.recover()
    check((-game.car.global_basis.z).dot(game.city_directions[1])>.99 and game.car.position.x>game.city_gates[1].x,"city recovery faces down the last completed street")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(profile))
    game.queue_free()
    await process_frame
    print("CITY_TESTS_DONE")
    quit(1 if failed else 0)
