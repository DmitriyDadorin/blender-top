extends SceneTree
var failed:=false
func check(ok:bool,label:String):
    print("PASS " if ok else "FAIL ",label)
    if not ok:failed=true
func _initialize():call_deferred("run")
func luminance(color:Color)->float:return(color.r+color.g+color.b)/3.0
func run():
    if DisplayServer.get_name()=="headless":
        push_error("Streetlight regression requires the graphical renderer")
        quit(2)
        return
    Engine.max_fps=60
    var game=load("res://game.tscn").instantiate()
    game.selected_map="city_night"
    game.skip_selection=true
    game.save_records=false
    root.add_child(game)
    current_scene=game
    game.set_process(false)
    game.audio_director.set_muted(true)
    game.audio_director.set_process(false)
    var world=game.get_node("World")
    world.set_process(false)
    world.get_node("Pedestrians").set_process(false)
    var night=world.get_node("NightLighting")
    night.set_process(false)
    game.car.set_physics_process(false)
    game.car.lights.set_process(false)
    game.car.lights.headlights_on=false
    game.car.lights.update_outputs()
    for layer in game.find_children("*","CanvasLayer",true,false):layer.hide()
    # Matte curbside spheres isolate street lighting from glass reflections,
    # headlight shadows and subpixel edges in the detailed production meshes.
    var samples:Array[Vector3]=[]
    for z in [380.0,340.0]:
        var probe:=MeshInstance3D.new()
        var mesh:=SphereMesh.new()
        mesh.radius=1
        mesh.height=2
        probe.mesh=mesh
        var material:=StandardMaterial3D.new()
        material.albedo_color=Color(.55,.55,.55)
        material.roughness=1
        probe.material_override=material
        probe.layers=2
        world.add_child(probe)
        probe.position=Vector3(5.5,1,z)
        samples.append(probe.position+Vector3(0,.7,.714))
    var previous_positions:Array[Vector3]=[]
    var previous_energy:Array[float]=[]
    var previous_values:Dictionary={}
    var lit_relocations:=0
    var maximum_step:=0.0
    var comparisons:=0
    for frame in 160:
        game.car.reset_at(Vector3(2.5,.055,420-frame*34.0/60.0))
        game.camera.position=game.car.position+Vector3(0,3.6,8.8)
        game.camera.look_at(game.car.position+Vector3(0,1.3,-7))
        night._process(1.0/60)
        for i in night.local_lights.size():
            var light:OmniLight3D=night.local_lights[i]
            if previous_positions.size()>i and light.position.distance_to(previous_positions[i])>1 and (previous_energy[i]>.02 or light.light_energy>.02):lit_relocations+=1
        previous_positions.clear()
        previous_energy.clear()
        for light in night.local_lights:
            previous_positions.append(light.position)
            previous_energy.append(light.light_energy)
        await process_frame
        await RenderingServer.frame_post_draw
        var image:Image=root.get_texture().get_image()
        for i in samples.size():
            var point:Vector3=samples[i]
            if point.distance_to(game.car.position)<12 or game.camera.is_position_behind(point):continue
            var pixel:=Vector2i(game.camera.unproject_position(point))
            if pixel.x<2 or pixel.y<2 or pixel.x>=image.get_width()-2 or pixel.y>=image.get_height()-2:continue
            var value:=0.0
            for dx in [-1,0,1]:
                for dy in [-1,0,1]:value+=luminance(image.get_pixelv(pixel+Vector2i(dx,dy)))/9
            if previous_values.has(i) and frame>12:
                maximum_step=maxf(maximum_step,absf(value-float(previous_values[i])))
                comparisons+=1
            previous_values[i]=value
        if frame in [35,36,37,70]:image.save_png("/private/tmp/streetlight_frame_%d.png"%frame)
    print("STREETLIGHT_STABILITY lit_relocations=",lit_relocations," maximum_brightness_step=",maximum_step," comparisons=",comparisons)
    check(lit_relocations==0,"street lights only move after fading completely out")
    check(comparisons>80 and maximum_step<.08,"curbside illumination changes smoothly along the straight")
    check(night.local_lights.size()==4,"night lighting retains the bounded four-light budget")
    game.queue_free()
    for i in 3:await process_frame
    print("STREETLIGHT_STABILITY_TESTS_DONE")
    quit(1 if failed else 0)
