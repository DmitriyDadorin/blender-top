extends Node
## Optional packaged-runtime verification, invoked only with --verify-export.
var checks:Array[Dictionary]=[]
var failed:=false
var metrics:Dictionary={}
func check(ok:bool,label:String)->void:
    checks.append({"ok":ok,"check":label})
    if not ok:failed=true
    print("PASS " if ok else "FAIL ",label)
func run(game:Node)->void:
    check(OS.get_name()=="macOS" and OS.has_feature("arm64"),"native Apple Silicon runtime")
    check(not OS.has_feature("editor"),"export template runtime")
    check(FileAccess.file_exists("res://assets/pacific_city.json") and FileAccess.file_exists("res://assets/palm_bay.json"),"packed collision metadata")
    check(OS.get_user_data_dir()==OS.get_data_dir().path_join("Godot/app_userdata/Машина — первый проект"),"legacy profile directory preserved after rename")
    var artwork:=load(ProjectSettings.get_setting("application/boot_splash/image")) as Texture2D
    check(artwork!=null and artwork.get_width()>=1000,"custom startup artwork included in application")
    if DisplayServer.get_name()!="headless":
        check(get_tree().root.title==str(ProjectSettings.get_setting("application/config/name")),"branded native window title")
    if "--verify-display" in OS.get_cmdline_user_args():
        await verify_display(game)
        finish()
        return
    if "--verify-crosswalks" in OS.get_cmdline_user_args():
        await verify_crosswalks(game)
        finish()
        return
    if "--verify-brakes" in OS.get_cmdline_user_args():
        await verify_brakes(game)
        finish()
        return
    game.audio_director.set_muted(true)
    for map_id in ["desert","city","city_night","palm_bay"]:
        game.select_map(map_id)
        for vehicle in ["classic","tourer"]:
            game.select_vehicle(vehicle)
            for i in 6:await get_tree().process_frame
            check(game.car.wheels.size()==4 and game.car.get_child_count()==2,map_id+" / "+vehicle)
        check(game.car.lights.headlights_on==(map_id=="city_night"),map_id+" automatic lights")
    game.start_race()
    game.countdown=.01
    for i in 12:await get_tree().physics_frame
    Input.action_press("accelerate")
    for i in 45:await get_tree().physics_frame
    Input.action_release("accelerate")
    check(game.car.speed>2 and game.car.position.y> -1,"driving on packaged terrain")
    if DisplayServer.get_name()!="headless":
        await RenderingServer.frame_post_draw
        for arg in OS.get_cmdline_user_args():
            if arg.begins_with("--verify-screenshot="):
                get_tree().root.get_texture().get_image().save_png(arg.trim_prefix("--verify-screenshot="))
    finish()

func frame_peak(count:int)->float:
    var previous:=Time.get_ticks_usec()
    var peak:=0.0
    for i in count:
        await get_tree().process_frame
        var now:=Time.get_ticks_usec()
        peak=maxf(peak,(now-previous)/1000.0)
        previous=now
    return peak

func verify_brakes(game:Node)->void:
    if DisplayServer.get_name()=="headless":
        check(false,"brake frame timing requires a graphical renderer")
        return
    var map_id:="palm_bay"
    var vehicle:="tourer"
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--verify-map="):map_id=arg.trim_prefix("--verify-map=")
        if arg.begins_with("--verify-vehicle="):vehicle=arg.trim_prefix("--verify-vehicle=")
    game.select_map(map_id)
    game.select_vehicle(vehicle)
    for i in 60:await get_tree().process_frame
    game.start_race()
    game.countdown=.01
    for i in 20:await get_tree().physics_frame
    var baseline:=await frame_peak(24)
    var limit:=clampf(baseline*4.0,100.0,250.0)
    metrics={"map":map_id,"vehicle":vehicle,"baseline_peak_ms":baseline,"limit_ms":limit}
    for action in ["handbrake","reverse"]:
        game.car.reset_at(game.map_start())
        for i in 24:await get_tree().process_frame
        game.car.speed=18
        Input.action_press(action)
        var peak:=await frame_peak(12)
        check(game.car.lights.braking and game.car.speed<18,action+" slows the moving car and lights the stop lamps")
        if action=="reverse":
            peak=maxf(peak,await frame_peak(85))
            check(game.car.speed<0 and game.car.lights.reversing,"holding reverse transitions to lit reverse lamps")
        Input.action_release(action)
        metrics[action+"_first_peak_ms"]=peak
        check(peak<limit,action+" first use has no long frame")
        for i in 24:await get_tree().process_frame
        game.car.reset_at(game.map_start())
        game.car.speed=18
        Input.action_press(action)
        var repeated:=await frame_peak(12)
        Input.action_release(action)
        metrics[action+"_repeat_peak_ms"]=repeated
        check(repeated<limit,action+" repeated use has no long frame")
    print("BRAKE_FRAME_TIMINGS ",JSON.stringify(metrics))

func crosswalk_samples(image:Image,camera:Camera3D,center:Vector3,basis:Basis)->Dictionary:
    var roughness:=0.0
    var contrast:=0.0
    var samples:=0
    # Camera projections use viewport coordinates; screenshots use framebuffer
    # pixels. Account for canvas scaling at fullscreen and other resolutions.
    var pixels:=camera.get_viewport().get_final_transform()
    for stripe in [-5,-3,-1,5]:
        for dx in [-.25,0.0,.25]:
            for dz in [-.8,-.4,0.0,.4,.8]:
                var pixel:=Vector2i(pixels*camera.unproject_position(center+basis*Vector3(stripe+dx,.0675,9+dz)))
                var asphalt:=Vector2i(pixels*camera.unproject_position(center+basis*Vector3(stripe+.7,.055,9+dz)))
                if pixel.x<2 or pixel.x>=image.get_width()-2 or pixel.y<2 or pixel.y>=image.get_height()-2:continue
                if not Rect2i(Vector2i.ZERO,image.get_size()).has_point(asphalt):continue
                var color:=image.get_pixelv(pixel)
                roughness+=absf(color.r-image.get_pixelv(pixel+Vector2i(1,0)).r)
                contrast+=color.r-image.get_pixelv(asphalt).r
                samples+=1
    return {"roughness":roughness/maxi(1,samples),"contrast":contrast/maxi(1,samples),"samples":samples}

func verify_crosswalks(game:Node)->void:
    if DisplayServer.get_name()=="headless":
        check(false,"crosswalk verification requires a graphical renderer")
        return
    game.audio_director.set_muted(true)
    game.set_process(false)
    game.car.set_physics_process(false)
    metrics={"crosswalk_views":[]}
    for map_id in ["city","city_night"]:
        game.state=game.RaceState.SELECTING
        game.select_map(map_id)
        game.state=game.RaceState.FINISHED
        game.camera.fov=68
        for layer in game.find_children("*","CanvasLayer",true,false):layer.hide()
        game.get_node("World/Pedestrians").hide()
        for vehicle in ["tourer","classic"]:
            game.selected_vehicle=vehicle
            game.install_vehicle(vehicle)
            for center in [Vector3(320,0,480),Vector3(-480,0,-480),Vector3(0,0,320)]:
                for direction in 4:
                    var yaw:=direction*PI*.5
                    var basis:=Basis(Vector3.UP,yaw)
                    var pos:Vector3=center+basis*Vector3(2.5,.055,10)
                    game.car.reset_at(pos,yaw)
                    var peak:=0.0
                    var contrast:=INF
                    var sample_count:=60
                    for offset in [0.0,.02]:
                        game.camera.position=pos+basis*Vector3(offset,3.6,8.8)
                        game.camera.look_at(pos+basis*Vector3(0,1.3,-7))
                        for i in 3:
                            await get_tree().process_frame
                            await RenderingServer.frame_post_draw
                        var image:=get_tree().root.get_texture().get_image()
                        var sample:=crosswalk_samples(image,game.camera,center,basis)
                        peak=maxf(peak,float(sample.roughness))
                        contrast=minf(contrast,float(sample.contrast))
                        sample_count=mini(sample_count,int(sample.samples))
                        if vehicle=="tourer" and center.x==320 and direction==3 and offset==0.0:
                            for arg in OS.get_cmdline_user_args():
                                if arg.begins_with("--verify-crosswalk-screenshot="):
                                    var path:=arg.trim_prefix("--verify-crosswalk-screenshot=")
                                    image.save_png(path if map_id=="city" else path.get_basename()+"-night.png")
                    metrics.crosswalk_views.append({"map":map_id,"vehicle":vehicle,"junction":[center.x,center.z],"direction":direction,"roughness":peak,"contrast":contrast,"samples":sample_count})
                    check(sample_count>=50 and peak<.04 and contrast>.02,"clean visible crosswalk: %s / %s / %s / heading %d"%[map_id,vehicle,Vector2(center.x,center.z),direction])
    var worst:=0.0
    for view in metrics.crosswalk_views:worst=maxf(worst,float(view.roughness))
    print("CROSSWALK_PIXEL_CHECK views=",metrics.crosswalk_views.size()," worst_roughness=",worst)

func display_frames(count:int=6)->void:
    for i in count:await get_tree().process_frame
    await RenderingServer.frame_post_draw

func display_image_fills_window(image:Image,window:Window)->bool:
    if image.get_size()!=window.size:return false
    for edge in [2,image.get_width()-3]:
        for height in [.2,.5,.8]:
            var color:=image.get_pixel(edge,int(image.get_height()*height))
            if color.r+color.g+color.b<.005:return false
    return true

func verify_display(game:Node)->void:
    if DisplayServer.get_name()=="headless":
        check(false,"display verification requires a graphical renderer")
        return
    process_mode=Node.PROCESS_MODE_ALWAYS
    game.audio_director.set_muted(true)
    game.select_map("palm_bay")
    var window:=get_tree().root
    window.mode=Window.MODE_WINDOWED
    await display_frames(40)
    var usable:=DisplayServer.screen_get_usable_rect(window.current_screen).size-Vector2i(100,100)
    metrics={"display_sizes":[]}
    var sizes:=[Vector2i(1280,720),Vector2i(1280,800),Vector2i(1680,720),Vector2i(1000,750),Vector2i(720,1000)]
    for requested in sizes:
        var fit:=minf(1.0,minf(float(usable.x)/requested.x,float(usable.y)/requested.y))
        window.size=Vector2i(Vector2(requested)*fit)
        game.state=game.RaceState.SELECTING
        game.garage_root.show()
        game.hud_root.hide()
        await display_frames()
        var viewport:Rect2=game.garage_root.get_global_rect()
        var header:Rect2=game.garage_root.get_node("GarageHeader").get_global_rect()
        var card:Rect2=game.garage_root.get_node("GarageCard").get_global_rect()
        check(absf(header.position.x-viewport.position.x-24)<2 and absf(header.end.x-viewport.end.x+24)<2 and absf(card.end.y-viewport.end.y+24)<2,"garage fits window "+str(requested))
        var image:=window.get_texture().get_image()
        var fills:=display_image_fills_window(image,window)
        check(fills,"3D image fills window without black side bars "+str(requested))
        metrics.display_sizes.append({"requested":[requested.x,requested.y],"actual":[window.size.x,window.size.y],"canvas":[viewport.size.x,viewport.size.y],"fills_window":fills})
        for arg in OS.get_cmdline_user_args():
            if arg.begins_with("--verify-display-screenshots="):
                var directory:=arg.trim_prefix("--verify-display-screenshots=")
                DirAccess.make_dir_recursive_absolute(directory)
                image.save_png(directory.path_join("%dx%d-garage.png"%[requested.x,requested.y]))
        game.garage_root.hide()
        game.hud_root.show()
        game.state=game.RaceState.FINISHED
        game.result_label.text="ФИНИШ!\nТвоё время: 01:20.00\nРекорд: 01:20.00\nВозвратов на дорогу: 0"
        game.camera_initialized=false
        game.result_panel.show()
        await display_frames()
        viewport=game.hud_root.get_global_rect()
        var result:Rect2=game.result_panel.get_global_rect()
        var pause:Rect2=game.pause_panel.get_global_rect()
        check(result.get_center().distance_to(viewport.get_center())<2 and pause.get_center().distance_to(viewport.get_center())<2,"finish and pause menus remain centered "+str(requested))
        var minimap:Rect2=game.mini_map.get_global_rect()
        var speed:Rect2=game.speed_label.get_global_rect()
        check(absf(minimap.end.x-viewport.end.x+24)<2 and absf(speed.end.x-viewport.end.x+20)<2,"minimap and speed stay at the right edge "+str(requested))
        for arg in OS.get_cmdline_user_args():
            if arg.begins_with("--verify-display-screenshots="):
                window.get_texture().get_image().save_png(arg.trim_prefix("--verify-display-screenshots=").path_join("%dx%d-finish.png"%[requested.x,requested.y]))
        game.result_panel.hide()
    game.state=game.RaceState.SELECTING
    game.garage_root.show()
    game.hud_root.hide()
    var key:=InputEventKey.new()
    key.physical_keycode=KEY_ENTER
    key.keycode=KEY_ENTER
    key.alt_pressed=true
    key.pressed=true
    Input.parse_input_event(key)
    key=key.duplicate()
    key.pressed=false
    Input.parse_input_event(key)
    await display_frames(50)
    check(game.is_fullscreen() and game.state==game.RaceState.SELECTING,"Alt+Enter enters fullscreen without starting a race")
    check(display_image_fills_window(window.get_texture().get_image(),window),"fullscreen image covers the display")
    game.state=game.RaceState.RACING
    game.toggle_pause()
    game.screen_buttons[0].pressed.emit()
    await display_frames(50)
    check(not game.is_fullscreen() and get_tree().paused,"pause-menu button returns to windowed mode while paused")
    game.toggle_pause()
    check(game.screen_buttons[1].text.begins_with("На весь экран"),"garage button reflects current display mode")
    print("DISPLAY_CHECK sizes=",metrics.display_sizes.size())

func finish()->void:
    var report:={"ok":not failed,"engine":Engine.get_version_info().string,"checks":checks,"metrics":metrics}
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--verify-report="):
            var file:=FileAccess.open(arg.trim_prefix("--verify-report="),FileAccess.WRITE)
            if file:file.store_string(JSON.stringify(report,"  "));file.close()
    print("MACOS_EXPORT_TESTS_DONE")
    get_tree().quit(1 if failed else 0)
