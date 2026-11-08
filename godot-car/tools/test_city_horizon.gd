extends SceneTree
var failed:=false
func check(ok:bool,description:String):
    print("PASS " if ok else "FAIL ",description)
    if not ok:failed=true
func _initialize():call_deferred("run")
func run():
    var game=load("res://game.tscn").instantiate()
    game.save_records=false
    game.skip_selection=true
    game.selected_map="city"
    root.add_child(game)
    current_scene=game
    for i in 4:await physics_frame
    var horizon=game.get_node("World/Horizon")
    check(horizon.building_count>=8000,"distant city extends beyond the playable blocks")
    check(horizon.get_node("Ocean") is MeshInstance3D and horizon.get_node("Beach") is MeshInstance3D,"ocean and beach fill the western horizon")
    check(horizon.get_node("Ocean").position.x<0,"ocean is on the west side")
    check(game.camera.far>=10000,"camera sees scenery beyond the old map edge")
    var skyline:Array[Node]=horizon.find_children("DistantDistrict*","MultiMeshInstance3D",false,false)
    check(skyline.size()>0 and skyline.size()<100,"distant buildings use a limited number of instanced batches")
    check(horizon.find_children("ExitMarker*","Node3D",false,false).size()==28,"all outgoing street ends have return markers")
    var street=game.get_node("World").find_child("StreetNetwork",true,false) as MeshInstance3D
    var clipped:=false
    var cutoff:float=-10000.0
    for i in street.mesh.get_surface_count():
        var mat=street.get_surface_override_material(i)
        if mat is ShaderMaterial and mat.shader.resource_path.ends_with("coastal_asphalt.gdshader"):
            clipped=true
            cutoff=float(mat.get_shader_parameter("coast_cutoff"))
    check(clipped,"old square asphalt is trimmed at the coast")
    var promenade=horizon.get_node("CoastalPromenade") as MeshInstance3D
    var land_edge:float=(promenade.global_transform*promenade.get_aabb().end).x
    check(cutoff>=land_edge,"asphalt stops before the promenade, with no coplanar overlap")
    game.state=game.RaceState.RACING
    game.car.enabled=false
    # Every main route point remains well inside the reduced zone.
    var bounds=load("res://scripts/city_world.gd")
    for pos in game.city_route:
        check(not bounds.outside_play_area(pos),"route point remains inside 510 m limit")
    var before:int=game.recoveries
    game.car.reset_at(Vector3(500,.2,0))
    game.message_timer=0
    game._process(1.0/60)
    check(game.recoveries==before and game.message_label.text.contains("Край"),"warning appears before automatic recovery")
    for pos in [Vector3(510,.2,0),Vector3(-510,.2,0),Vector3(0,.2,510),Vector3(0,.2,-510)]:
        game.car.reset_at(pos)
        game._process(1.0/60)
        check(game.recoveries==before,"inside edge does not reset the car")
    game.next_gate=2
    for pos in [Vector3(511,.2,0),Vector3(-511,.2,0),Vector3(0,.2,511),Vector3(0,.2,-511)]:
        game.car.reset_at(pos)
        var old_time:float=game.elapsed
        game._process(1.0/60)
        before+=1
        check(game.recoveries==before and game.car.position.distance_to(Vector3(323.5,.2,322.5))<.01 and game.elapsed>=old_time+5,"exit returns to the last checkpoint with penalty")
    game.queue_free()
    await process_frame
    print("CITY_HORIZON_TESTS_DONE")
    quit(1 if failed else 0)
