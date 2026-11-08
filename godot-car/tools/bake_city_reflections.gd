extends SceneTree
func _initialize():call_deferred("run")
func rendered_frames(count:int):
    for i in count:
        await process_frame
        await RenderingServer.frame_post_draw
func run():
    if DisplayServer.get_name()=="headless":
        push_error("Reflection baking requires a graphical renderer")
        quit(2)
        return
    root.content_scale_size=Vector2i(256,256)
    root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
    root.size=Vector2i(256,256)
    DisplayServer.window_set_size(Vector2i(256,256))
    var game=load("res://game.tscn").instantiate()
    game.save_records=false
    root.add_child(game)
    current_scene=game
    var night:="night" in OS.get_cmdline_user_args()
    game.select_map("city_night" if night else "city")
    game.start_race()
    game.countdown=.01
    await rendered_frames(4)
    game.car.enabled=false
    game.car.hide()
    game.get_node("World/Pedestrians").hide()
    game.get_node("World/Pedestrians").set_process(false)
    game.route_guides.hide()
    for gate in game.gate_nodes:gate.hide()
    game.state=game.RaceState.FINISHED
    game.set_process(false)
    for layer in game.find_children("*","CanvasLayer",true,false):layer.hide()
    # Avoid accumulating reflections from previous bakes inside the next atlas.
    for ob in game.find_children("Block_*","MeshInstance3D",true,false):
        for index in ob.mesh.get_surface_count():
            var material=ob.get_surface_override_material(index)
            if material is ShaderMaterial:
                material.set_shader_parameter("reflection_amount",0.0)
    for ob in game.find_children("Enriched_ParkedCars*","MeshInstance3D",true,false):
        for index in ob.mesh.get_surface_count():
            var material=ob.get_surface_override_material(index)
            if material is ShaderMaterial:material.set_shader_parameter("reflection_amount",0.0)
    var camera:Camera3D=game.camera
    camera.fov=90
    camera.near=.5
    camera.far=6000
    var directions:Array[Vector3]=[Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.BACK,Vector3.FORWARD]
    var ups:Array[Vector3]=[Vector3.UP,Vector3.UP,Vector3.FORWARD,Vector3.BACK,Vector3.UP,Vector3.UP]
    for location in [-240.0,240.0]:
        camera.position=Vector3(0,35,location)
        await rendered_frames(32)
        var images:Array[Image]=[]
        for i in 6:
            camera.look_at(camera.position+directions[i],ups[i])
            await rendered_frames(3)
            var image:=root.get_texture().get_image()
            image.resize(256,256,Image.INTERPOLATE_LANCZOS)
            image.convert(Image.FORMAT_RGBA8)
            image.generate_mipmaps()
            images.append(image)
        var atlas:=Image.create(768,512,false,Image.FORMAT_RGBA8)
        for i in 6:
            atlas.blit_rect(images[i],Rect2i(0,0,256,256),Vector2i((i%3)*256,(i/3)*256))
        var name:="north" if location<0 else "south"
        assert(atlas.save_png("res://textures/"+("city_night_reflection_" if night else "city_reflection_")+name+".png")==OK)
        print("REFLECTION_BAKED ",name)
    quit()
