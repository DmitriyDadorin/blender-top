extends SceneTree
# GPU regression: small camera movements must not swap the promenade and asphalt.
func _initialize():call_deferred("run")
func run():
    if DisplayServer.get_name()=="headless":
        push_error("Run this check with a graphical renderer, without --headless")
        quit(2)
        return
    var city=load("res://city.tscn").instantiate()
    root.add_child(city)
    var cam=city.get_node("Camera3D") as Camera3D
    cam.current=true
    cam.fov=68
    cam.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
    Engine.time_scale=0
    var previous:Array[Color]=[]
    var peak:=0.0
    var total:=0.0
    var jumps:=0
    for frame in 12:
        cam.position=Vector3(-462,3.6+frame*.002,-320)
        cam.look_at(Vector3(-530,.055,-320))
        await process_frame
        await RenderingServer.frame_post_draw
        var img:=root.get_texture().get_image()
        var colors:Array[Color]=[]
        for x in range(-513,-495,2):
            for z in range(-340,-300,2):
                var pixel:=cam.unproject_position(Vector3(x,.055,z))
                var p:=Vector2i(roundi(pixel.x),roundi(pixel.y))
                if p.x<0 or p.x>=img.get_width() or p.y<0 or p.y>=img.get_height():continue
                colors.append(img.get_pixelv(p))
        if previous.size()==colors.size():
            for i in colors.size():
                var diff:=Vector3(colors[i].r-previous[i].r,colors[i].g-previous[i].g,colors[i].b-previous[i].b).length()
                peak=maxf(peak,diff)
                total+=diff
                if diff>.1:jumps+=1
        previous=colors
    print("COAST_PIXEL_FLICKER total=",total," peak=",peak," large_changes=",jumps)
    var stable:=total<10.0 and jumps<40
    print("PASS stable coastal surface" if stable else "FAIL coastal depth fighting")
    quit(0 if stable else 1)
