extends SceneTree
var failed:=false
func check(ok:bool,label:String):
    print("PASS " if ok else "FAIL ",label)
    if not ok:failed=true
func _initialize():call_deferred("run")
func capture()->Image:
    for i in 6:
        await process_frame
        await RenderingServer.frame_post_draw
    return root.get_texture().get_image()
func luminance(c:Color)->float:return(c.r+c.g+c.b)/3
func run():
    if DisplayServer.get_name()=="headless":
        push_error("Use a graphical renderer for the light comparison")
        quit(2)
        return
    var game=load("res://game.tscn").instantiate()
    game.skip_selection=true
    game.save_records=false
    game.selected_map="city_night"
    root.add_child(game)
    current_scene=game
    game.state=game.RaceState.FINISHED
    game.set_process(false)
    game.get_node("World").set_process(false)
    game.get_node("World/Pedestrians").set_process(false)
    for layer in game.find_children("*","CanvasLayer",true,false):layer.hide()
    var camera:Camera3D=game.camera
    var night=game.get_node("World/NightLighting")
    for vehicle in ["classic","tourer"]:
        game.install_vehicle(vehicle)
        game.car.set_physics_process(false)
        game.car.reset_at(Vector3(2.5,.055,420))
        var lamps=game.car.lights
        lamps.set_process(false)
        camera.fov=68
        camera.position=game.car.position+Vector3(0,3.6,8.8)
        camera.look_at(game.car.position+Vector3(0,1.3,-7))
        night.update_lights()
        night.set_process(false)
        lamps.headlights_on=false
        lamps.update_outputs()
        var dark:Image=await capture()
        lamps.headlights_on=true
        lamps.update_outputs()
        var lit:Image=await capture()
        var difference:=0.0
        var samples:=0
        var illuminated:=0
        for distance in [8,12,16,20,24,28,32]:
            for offset in [-1.5,0.0,1.5]:
                var p:Vector3=game.car.position+Vector3(offset,.006,-distance)
                var pixel:=Vector2i(camera.unproject_position(p))
                var delta:=luminance(lit.get_pixelv(pixel))-luminance(dark.get_pixelv(pixel))
                difference+=delta
                samples+=1
                if delta>.025:illuminated+=1
        print("NIGHT_BEAMS ",vehicle," mean_delta=",difference/samples," illuminated_samples=",illuminated)
        check(difference/samples>.02 and illuminated>=10,"real low beams illuminate the road ahead on "+vehicle)
        camera.fov=55
        camera.position=game.car.position+Vector3(2.6,1.6,5.3)
        camera.look_at(game.car.position+Vector3(0,.8,0))
        lamps.set_driver_state(false,false)
        var tail:Image=await capture()
        lamps.set_driver_state(true,false)
        var brake:Image=await capture()
        var bright_red:=0
        for y in range(0,tail.get_height(),2):
            for x in range(0,tail.get_width(),2):
                var a:=tail.get_pixel(x,y)
                var b:=brake.get_pixel(x,y)
                if b.r>.7 and b.r>a.r+.2 and b.r>b.g*2:bright_red+=1
        print("NIGHT_BRAKE ",vehicle," bright_red_samples=",bright_red)
        check(bright_red>30,"actual rear lenses brighten when braking on "+vehicle)
        lamps.set_driver_state(false,false)
    # Sample steady gameplay with pedestrians and automatic beams active.
    game.get_node("World/Pedestrians").set_process(true)
    game.car.lights.set_process(true)
    camera.position=game.car.position+Vector3(0,3.6,8.8)
    camera.look_at(game.car.position+Vector3(0,1.3,-7))
    var times:Array[float]=[]
    for i in 75:
        var start:=Time.get_ticks_usec()
        await process_frame
        await RenderingServer.frame_post_draw
        if i>15:times.append((Time.get_ticks_usec()-start)/1000.0)
    times.sort()
    print("NIGHT_FRAME_TIME median_ms=",times[times.size()/2]," p95_ms=",times[int(times.size()*.95)])
    print("NIGHT_RENDER_TESTS_DONE")
    quit(1 if failed else 0)
