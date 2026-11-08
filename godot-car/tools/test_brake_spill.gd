extends SceneTree
var failed:=false
func check(ok:bool,label:String):
    print("PASS " if ok else "FAIL ",label)
    if not ok:failed=true
func _initialize():call_deferred("run")
func capture()->Image:
    for i in 4:
        await process_frame
        await RenderingServer.frame_post_draw
    return root.get_texture().get_image()
func red_at(image:Image,camera:Camera3D,point:Vector3)->float:
    var pixel:=Vector2i(camera.unproject_position(point))
    return image.get_pixelv(pixel).r
func run():
    if DisplayServer.get_name()=="headless":
        push_error("Brake spill regression requires the graphical renderer")
        quit(2)
        return
    var world:=Node3D.new()
    root.add_child(world)
    current_scene=world
    var settings:=Environment.new()
    settings.background_mode=Environment.BG_COLOR
    settings.background_color=Color(.055,.065,.08)
    settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
    settings.ambient_light_color=Color(.7,.75,.85)
    settings.ambient_light_energy=.3
    var environment:=WorldEnvironment.new()
    environment.environment=settings
    world.add_child(environment)
    var sun:=DirectionalLight3D.new()
    sun.name="Sun"
    sun.light_energy=.35
    sun.rotation_degrees=Vector3(-40,-40,0)
    world.add_child(sun)
    var ground:=MeshInstance3D.new()
    var plane:=PlaneMesh.new()
    plane.size=Vector2(30,30)
    ground.mesh=plane
    var gray:=StandardMaterial3D.new()
    gray.albedo_color=Color(.25,.25,.25)
    ground.material_override=gray
    world.add_child(ground)
    var camera:=Camera3D.new()
    camera.projection=Camera3D.PROJECTION_ORTHOGONAL
    camera.size=6.6
    world.add_child(camera)
    camera.current=true
    for vehicle in ["classic","tourer"]:
        var car=load("res://scripts/car_controller.gd").new()
        world.add_child(car)
        var model=load("res://assets/"+("car" if vehicle=="classic" else "grand_tourer")+".glb").instantiate()
        car.add_child(model)
        car.setup(model)
        car.set_physics_process(false)
        car.lights.set_process(false)
        car.lights.headlights_on=false
        car.lights.update_outputs()
        camera.position=Vector3(0,1.7,7)
        camera.look_at(Vector3(0,.8,0))
        var off:Image=await capture()
        car.lights.set_driver_state(true,false)
        var on:Image=await capture()
        var rear_z:float=car.lights.rear_positions[0].z
        var body_change:=0.0
        for x in [-.2,0.0,.2]:
            for y in [.8,.9,1.15]:
                var point:=Vector3(x,y,rear_z)
                body_change=maxf(body_change,absf(red_at(on,camera,point)-red_at(off,camera,point)))
        var lens_change:=0.0
        for point in car.lights.rear_positions:
            lens_change+=red_at(on,camera,point)-red_at(off,camera,point)
        lens_change/=2
        var ground_point:=Vector3(0,.003,rear_z+1.5)
        var ground_change:=red_at(on,camera,ground_point)-red_at(off,camera,ground_point)
        print("BRAKE_SPILL ",vehicle," body_red_delta=",body_change," lens_red_delta=",lens_change," ground_red_delta=",ground_change)
        check(body_change<.025,"braking does not illuminate the boot and body on "+vehicle)
        check(lens_change>.2,"actual rear lenses still brighten on "+vehicle)
        check(ground_change>.01,"rear-directed stop lamps retain a soft road spill on "+vehicle)
        camera.position=Vector3(8,2.5,0)
        camera.look_at(Vector3(0,.7,0))
        car.lights.set_driver_state(false,false)
        off=await capture()
        car.lights.set_driver_state(true,false)
        on=await capture()
        body_change=0
        for z in [-1.1,-.4,.4,1.2]:
            var point:=Vector3(.9,.8,z)
            body_change=maxf(body_change,absf(red_at(on,camera,point)-red_at(off,camera,point)))
        check(body_change<.025,"braking leaves the side panels unlit on "+vehicle)
        car.queue_free()
        await process_frame
    world.queue_free()
    for i in 3:await process_frame
    print("BRAKE_SPILL_TESTS_DONE")
    quit(1 if failed else 0)
