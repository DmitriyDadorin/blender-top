extends SceneTree
## A GPU regression: tall buildings must shade the road; a car cannot darken
## the same completely occluded sunlight a second time.
var failed:=false
func check(ok:bool,description:String):
    print("PASS " if ok else "FAIL ",description)
    if not ok:failed=true
func _initialize():call_deferred("run")
func capture()->Image:
    for i in 4:
        await process_frame
        await RenderingServer.frame_post_draw
    return root.get_texture().get_image()
func luminance(c:Color)->float:return(c.r+c.g+c.b)/3.0
func car_rect(meshes:Array,camera:Camera3D)->Rect2:
    var pixels:Array[Vector2]=[]
    for ob in meshes:
        var bounds:AABB=ob.get_aabb()
        for i in 8:pixels.append(camera.unproject_position(ob.global_transform*bounds.get_endpoint(i)))
    var rect:=Rect2(pixels[0],Vector2.ZERO)
    for pixel in pixels:rect=rect.expand(pixel)
    return rect.grow(3)
func run():
    if DisplayServer.get_name()=="headless":
        push_error("Shadow verification needs a graphical renderer")
        quit(2)
        return
    var game=load("res://game.tscn").instantiate()
    game.save_records=false
    game.skip_selection=true
    game.selected_map="city"
    root.add_child(game)
    current_scene=game
    game.car.enabled=false
    game.car.set_physics_process(false)
    game.state=game.RaceState.FINISHED
    game.set_process(false)
    var world=game.get_node("World")
    world.set_process(false)
    world.get_node("Pedestrians").set_process(false)
    world.get_node("Pedestrians").hide()
    for layer in game.find_children("*","CanvasLayer",true,false):layer.hide()
    var sun:DirectionalLight3D=world.get_node("Sun")
    if "baseline" in OS.get_cmdline_user_args():sun.directional_shadow_pancake_size=20.0
    var camera:Camera3D=game.camera
    camera.fov=68
    await physics_frame
    var space:PhysicsDirectSpaceState3D=world.get_world_3d().direct_space_state
    for vehicle in ["classic","tourer"]:
        game.install_vehicle(vehicle)
        var meshes:Array=game.car.find_children("*","MeshInstance3D",true,false)
        for pos in [Vector3(322.5,.055,-81),Vector3(-2.5,.055,-282.25),Vector3(2.5,.055,420)]:
            game.car.reset_at(pos)
            camera.position=pos+Vector3(0,3.6,8.8)
            camera.look_at(pos+Vector3(0,1.3,-7))
            if pos.z>0:
                camera.position=pos+Vector3(5,9,8)
                camera.look_at(pos)
            sun.shadow_enabled=true
            for ob in meshes:
                ob.show()
                ob.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if pos.z>0 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
            var all_shadows:Image=await capture()
            var excluded:=car_rect(meshes,camera)
            for ob in meshes:
                if pos.z>0:ob.hide()
                else:ob.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            var building_shadows:Image=await capture()
            sun.shadow_enabled=false
            var unshadowed:Image=await capture()
            var blocked:=0;var missing:=0;var doubled:=0;var sunlit_car_shadow:=0
            for dx in range(-20,21):
                for dz in range(-20,21):
                    var point:Vector3=pos+Vector3(dx*.25,.025,dz*.25)
                    var pixel:Vector2=camera.unproject_position(point)
                    if (pos.z<0 and excluded.has_point(pixel)) or not Rect2(Vector2.ZERO,all_shadows.get_size()).has_point(pixel):continue
                    var a:=luminance(all_shadows.get_pixelv(Vector2i(pixel)))
                    var b:=luminance(building_shadows.get_pixelv(Vector2i(pixel)))
                    var c:=luminance(unshadowed.get_pixelv(Vector2i(pixel)))
                    var query:=PhysicsRayQueryParameters3D.create(point,point+sun.global_basis.z*500)
                    query.exclude=[game.car.get_rid()]
                    var occluded:=not space.intersect_ray(query).is_empty()
                    if occluded:
                        blocked+=1
                        if b>c*.82:missing+=1
                        elif b-a>.02:doubled+=1
                    elif b-a>.03:sunlit_car_shadow+=1
            print("CITY_SHADOW ",vehicle," ",pos," occluded=",blocked," missing=",missing," double=",doubled," sunlit_car_shadow=",sunlit_car_shadow)
            if pos.z<0:
                check(blocked>100 and float(missing)/maxi(1,blocked)<.08,"tall building shadows cover the nearby road")
                check(doubled<3,"car shadow merges into full building shade")
            else:
                check(sunlit_car_shadow>5,"car still casts its own shadow in sunlight")
    print("CITY_SHADOW_TESTS_DONE")
    quit(1 if failed else 0)
