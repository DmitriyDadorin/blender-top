extends SceneTree
func _initialize():call_deferred("run")
func run():
    if DisplayServer.get_name()=="headless":
        push_error("Run with a graphical renderer, without --headless")
        quit(2)
        return
    var city=load("res://city.tscn").instantiate()
    root.add_child(city)
    var block=city.find_child("Block_3_3",true,false) as MeshInstance3D
    for ob in city.find_children("*","MeshInstance3D",true,false):
        if ob!=block:ob.hide()
    city.get_node("Horizon").hide()
    var camera=city.get_node("Camera3D") as Camera3D
    camera.current=true
    camera.fov=68
    Engine.time_scale=0
    var samples:Array[Vector3]=[]
    var seen:Dictionary={}
    for index in block.mesh.get_surface_count():
        if not block.mesh.surface_get_material(index).resource_name.begins_with("City_Baked"):continue
        var arrays:Array=block.mesh.surface_get_arrays(index)
        var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
        var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
        var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
        for i in range(0,indices.size(),3):
            if normals[indices[i]].z<.95:continue
            var a:Vector3=vertices[indices[i]]
            var b:Vector3=vertices[indices[i+1]]
            var c:Vector3=vertices[indices[i+2]]
            var low:Vector3=a.min(b).min(c)
            var high:Vector3=a.max(b).max(c)
            var key:=str(low)+str(high)
            if seen.has(key):continue
            seen[key]=true
            var x:=low.x+2.1
            while x<high.x-1:
                var y:=7.15
                while y<high.y-2:
                    samples.append(block.global_transform*Vector3(x,y,high.z))
                    y+=3.8
                x+=3.6
    # Allow rendering to settle at the actual test viewpoint before measuring.
    camera.position=Vector3(80,42,700)
    camera.look_at(Vector3(80,42,80))
    for i in 32:
        await process_frame
        await RenderingServer.frame_post_draw
    var previous:Array[Color]=[]
    var changes:=0
    var comparisons:=0
    for frame in 14:
        camera.position=Vector3(80,42+frame*.002,700)
        camera.look_at(Vector3(80,42,80))
        await process_frame
        await RenderingServer.frame_post_draw
        var img:=root.get_texture().get_image()
        var colors:Array[Color]=[]
        for point in samples:
            var pixel:=Vector2i(camera.unproject_position(point))
            if pixel.x<0 or pixel.y<0 or pixel.x>=img.get_width() or pixel.y>=img.get_height():continue
            colors.append(img.get_pixelv(pixel))
        if colors.size()==previous.size():
            for i in colors.size():
                var delta:=Vector3(colors[i].r-previous[i].r,colors[i].g-previous[i].g,colors[i].b-previous[i].b).length()
                if delta>.12:changes+=1
                comparisons+=1
        previous=colors
    var ratio:=float(changes)/maxi(1,comparisons)
    print("WINDOW_RENDER samples=",samples.size()," comparisons=",comparisons," abrupt_change_fraction=",ratio)
    var stable:=samples.size()>100 and comparisons>1000 and ratio<.025
    print("PASS stable window facades during camera motion" if stable else "FAIL window flicker")
    quit(0 if stable else 1)
