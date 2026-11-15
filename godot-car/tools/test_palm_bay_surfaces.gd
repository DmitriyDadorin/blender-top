extends SceneTree
var failed:=false
var surfaces:Array[Dictionary]=[]
func check(ok:bool,label:String)->void:
    print("PASS " if ok else "FAIL ",label)
    if not ok:failed=true
func _initialize():call_deferred("run")
func collect(world:Node3D)->void:
    for ob in world.get_node("ArtGeometry").find_children("*","MeshInstance3D",true,false):
        for index in ob.mesh.get_surface_count():
            var material:Material=ob.mesh.surface_get_material(index)
            if not material:continue
            var title:String=material.resource_name
            var terrain:=false
            for key in ["road","grass","walk","sand","ocean"]:
                if title.begins_with("PalmBay_"+key):terrain=true
            if not terrain:continue
            var arrays:Array=ob.mesh.surface_get_arrays(index)
            var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
            var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
            if indices.is_empty():
                for i in vertices.size():indices.append(i)
            for i in range(0,indices.size(),3):
                var a:Vector3=ob.global_transform*vertices[indices[i]]
                var b:Vector3=ob.global_transform*vertices[indices[i+1]]
                var c:Vector3=ob.global_transform*vertices[indices[i+2]]
                if maxf(absf(a.y),maxf(absf(b.y),absf(c.y)))>.005:continue
                surfaces.append({"a":Vector2(a.x,a.z),"b":Vector2(b.x,b.z),"c":Vector2(c.x,c.z)})
func coverage(point:Vector2)->int:
    var count:=0
    for face in surfaces:
        var ab:Vector2=face.b-face.a
        var ac:Vector2=face.c-face.a
        var ap:Vector2=point-face.a
        var det:=ab.cross(ac)
        if absf(det)<.00001:continue
        var u:=ap.cross(ac)/det
        var v:=ab.cross(ap)/det
        if u>.000001 and v>.000001 and u+v<.999999:count+=1
    return count
func brightness(color:Color)->float:return(color.r+color.g+color.b)/3
func run():
    var game=load("res://game.tscn").instantiate()
    game.selected_map="palm_bay"
    game.skip_selection=true
    game.save_records=false
    root.add_child(game)
    current_scene=game
    game.set_process(false)
    game.set_physics_process(false)
    game.car.set_physics_process(false)
    game.car.lights.set_process(false)
    game.audio_director.set_muted(true)
    game.audio_director.set_process(false)
    var world=game.get_node("World")
    collect(world)
    for point in [Vector2(-319.37,-319.21),Vector2(-159.2,1.4),Vector2(2.123,83.47),Vector2(317.81,322.19),Vector2(42.123,42.456),Vector2(70.5,-47.2),Vector2(-110.21,-90.32),Vector2(800,901),Vector2(-370,25.3),Vector2(-390,82.1)]:
        check(coverage(point)==1,"one terrain surface at "+str(point))
    check(game.camera.near>=.3,"camera preserves depth precision for roads and horizon")
    if DisplayServer.get_name()!="headless":
        Engine.max_fps=60
        # Isolate depth/paint stability from cascade-shadow rasterization.
        world.get_node("Sun").shadow_enabled=false
        for layer in game.find_children("*","CanvasLayer",true,false):layer.hide()
        for gate in game.gate_nodes:gate.hide()
        game.route_guides.hide()
        var samples:Array[Vector3]=[]
        for i in 45:samples.append(Vector3(-193+i*1.7,.001,-318.23))
        var previous:Dictionary={}
        var comparisons:=0
        var flashes:=0
        for frame in 100:
            game.car.reset_at(Vector3(-220+frame*.35,.05,-317.5),-PI*.5)
            game.camera.position=game.car.position+Vector3(-8.8,3.6,0)
            game.camera.look_at(game.car.position+Vector3(7,1.3,0))
            await process_frame
            await RenderingServer.frame_post_draw
            var image:Image=root.get_texture().get_image()
            for i in samples.size():
                var point:=samples[i]
                if point.distance_to(game.car.position)<14 or game.camera.is_position_behind(point):continue
                var pixel:=Vector2i(game.camera.unproject_position(point))
                if pixel.x<2 or pixel.y<2 or pixel.x>=image.get_width()-2 or pixel.y>=image.get_height()-2:continue
                var value:=0.0
                for dx in [-1,0,1]:
                    for dy in [-1,0,1]:value+=brightness(image.get_pixelv(pixel+Vector2i(dx,dy)))/9
                if previous.has(i) and frame>12:
                    comparisons+=1
                    if absf(value-float(previous[i]))>.12:flashes+=1
                previous[i]=value
        var fraction:=float(flashes)/maxi(1,comparisons)
        print("PALM_ROAD_STABILITY comparisons=",comparisons," flash_fraction=",fraction)
        check(comparisons>1000 and fraction<.015,"road paint and intersections stay stable while driving")
        var final_image:Image=root.get_texture().get_image()
        var horizon_pixel:=Vector2i(game.camera.unproject_position(Vector3(2200,0,-340)))
        var horizon_color:=final_image.get_pixelv(horizon_pixel)
        var delta:=Vector3(horizon_color.r-.96,horizon_color.g-.56,horizon_color.b-.41).length()
        check(delta<.04,"distant ground blends into the sunset sky without a hard horizon edge")
    game.queue_free()
    for i in 3:await process_frame
    print("PALM_SURFACE_TESTS_DONE")
    quit(1 if failed else 0)
