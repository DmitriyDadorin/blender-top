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
    var world=game.get_node("World")
    var life=world.get_node("Pedestrians")
    life.set_process(false)
    var counts:Dictionary=world.metadata.city_life
    check(counts.parked_cars==154 and counts.trees==306 and counts.bins==144,"Blender dressing metadata matches imported scene")
    check(world.find_child("Enriched_ParkedCars",true,false)!=null and world.find_child("Enriched_Landscaping",true,false)!=null,"new Blender car and landscape meshes are present")
    check(life.walkers.size()==144,"144 sidewalk walkers are installed once")
    var walker:Dictionary=life.walkers[0]
    walker.offset=0.0
    life.time=0
    life.update_walkers(1.0)
    var a:Vector3=walker.node.position
    life.update_walkers(2.0)
    var b:Vector3=walker.node.position
    check(a.distance_to(b)>1.8,"pedestrians move along the sidewalk")
    life.time=float(walker.duration)+.3
    life.update_walkers(0)
    a=walker.node.position
    life.update_walkers(.7)
    check(a.is_equal_approx(walker.node.position),"pedestrians pause at the end of a path")
    life.time=float(walker.duration)+3
    life.update_walkers(0)
    a=walker.node.position
    life.update_walkers(2)
    b=walker.node.position
    check((b-a).dot((walker.b-walker.a).normalized())< -1.8,"pedestrians walk back in the opposite direction")
    check(walker.node.find_child("ClothedTorso",true,false).mesh!=null and walker.node.find_child("Face",true,false).mesh!=null,"sculpted clothing and face geometry are present")
    var phase_before:float=walker.phase
    var pose_before:Transform3D=walker.node.transform
    walker.phase=0.0
    walker.node.rotation=Vector3.ZERO
    life.animate_walker(walker,.10,1.0)
    walker.node.position=Vector3(0,.18,-.10)
    var planted_a:Vector3=walker.legs[0].foot.global_position
    life.animate_walker(walker,.12,1.0)
    walker.node.position=Vector3(0,.18,-.12)
    var planted_b:Vector3=walker.legs[0].foot.global_position
    check(planted_a.distance_to(planted_b)<.003,"stance foot stays planted as the body advances")
    check(absf(planted_b.y-(.18+.085*float(walker.node.scale.y)))<.004,"stance foot remains at ground contact height")
    check(absf(walker.legs[0].knee.rotation.x)>.1,"knees articulate during a step")
    life.animate_walker(walker,.8*float(walker.node.scale.z),1.0)
    check(walker.legs[0].foot.global_position.y>planted_b.y+.08,"swing foot clears the ground")
    walker.node.transform=pose_before
    walker.phase=phase_before
    var safe:=true
    await physics_frame
    var space:PhysicsDirectSpaceState3D=world.get_world_3d().direct_space_state
    for person in life.walkers:
        var box:=BoxShape3D.new()
        box.size=Vector3(.55,1.65,.55)
        var query:=PhysicsShapeQueryParameters3D.new()
        query.shape=box
        for i in 7:
            query.transform.origin=person.a.lerp(person.b,float(i)/6)+Vector3(0,.9,0)
            if not space.intersect_shape(query,1).is_empty():safe=false
    check(safe,"all pedestrian paths clear buildings, trees, bins and parked cars")
    life.set_process(true)
    var old_time:float=life.time
    paused=true
    for i in 3:await process_frame
    check(life.time==old_time,"paused city does not advance pedestrians")
    paused=false
    print("CITY_LIFE_TESTS_DONE length_m=",game.city_course_length())
    quit(1 if failed else 0)
