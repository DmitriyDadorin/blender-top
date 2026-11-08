extends SceneTree
var failed:=false
func check(ok:bool,label:String):
    print("PASS " if ok else "FAIL ",label)
    if not ok:failed=true
func _initialize():call_deferred("run")
func capture(frames:int=2)->Image:
    for i in frames:
        await process_frame
        await RenderingServer.frame_post_draw
    return root.get_texture().get_image()
func brightness(c:Color)->float:return(c.r+c.g+c.b)/3.0
func run():
    if DisplayServer.get_name()=="headless":
        push_error("This regression needs a graphical renderer")
        quit(2)
        return
    if "baseline" in OS.get_cmdline_user_args():root.positional_shadow_atlas_16_bits=true
    print("HEADLIGHT_DEPTH_16_BITS ",root.positional_shadow_atlas_16_bits)
    var game=load("res://game.tscn").instantiate()
    game.skip_selection=true
    game.save_records=false
    game.selected_map="city_night"
    root.add_child(game)
    current_scene=game
    game.state=game.RaceState.FINISHED
    game.set_process(false)
    var world=game.get_node("World")
    world.set_process(false)
    world.get_node("Pedestrians").set_process(false)
    for layer in game.find_children("*","CanvasLayer",true,false):layer.hide()
    var camera:Camera3D=game.camera
    camera.fov=68
    var building:Dictionary={}
    for entry in world.metadata.colliders:
        if entry.position[0]==45 and entry.position[2]==275 and entry.size[1]>10:building=entry;break
    check(not building.is_empty(),"intersection facade is available for sampling")
    if building.is_empty():quit(1);return
    var samples:Array[Vector3]=[]
    var x:float=building.position[0]-building.size[0]*.5+1.0
    while x<building.position[0]+building.size[0]*.5-1.0:
        for y in [.8,1.1,1.4,1.7,2.0,2.3,4.1,5.0]:samples.append(Vector3(x,y,building.position[2]+building.size[2]*.5+.003))
        x+=.14
    for vehicle in ["classic","tourer"]:
        game.install_vehicle(vehicle)
        game.car.set_physics_process(false)
        game.car.lights.set_process(false)
        game.car.reset_at(Vector3(2.5,.055,340),-.55)
        camera.position=game.car.position+game.car.basis*Vector3(0,3.6,8.8)
        camera.look_at(game.car.position+Vector3(0,1.3,0)-game.car.basis.z*7)
        world.get_node("NightLighting").update_lights()
        world.get_node("NightLighting").set_process(false)
        await capture(12)
        var previous:Array[float]=[]
        var changes:=0
        var comparisons:=0
        var streaks:=0
        var edges:=0
        for frame in 20:
            # Track the same world points while the car and its lights move 48 cm.
            game.car.reset_at(Vector3(2.5+frame*.025,.055,340),-.55)
            camera.position=game.car.position+game.car.basis*Vector3(0,3.6,8.8)
            camera.look_at(game.car.position+Vector3(0,1.3,0)-game.car.basis.z*7)
            var image:Image=await capture()
            var values:Array[float]=[]
            for point in samples:
                var pixel:=Vector2i(camera.unproject_position(point))
                values.append(brightness(image.get_pixelv(pixel)))
            for i in range(8,values.size()):
                if absf(values[i]-values[i-8])>.2:streaks+=1
                edges+=1
            if previous.size()==values.size():
                for i in values.size():
                    if absf(values[i]-previous[i])>.13:changes+=1
                    comparisons+=1
            previous=values
        var fraction:=float(changes)/maxi(1,comparisons)
        print("HEADLIGHT_STABILITY ",vehicle," samples=",samples.size()," comparisons=",comparisons," flashing_fraction=",fraction," streak_fraction=",float(streaks)/maxi(1,edges))
        check(comparisons>10000 and fraction<.02 and float(streaks)/maxi(1,edges)<.03,"facade illumination stays stable while "+vehicle+" moves")
    print("HEADLIGHT_STABILITY_TESTS_DONE")
    quit(1 if failed else 0)
