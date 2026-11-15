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

func finish()->void:
    var report:={"ok":not failed,"engine":Engine.get_version_info().string,"checks":checks,"metrics":metrics}
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--verify-report="):
            var file:=FileAccess.open(arg.trim_prefix("--verify-report="),FileAccess.WRITE)
            if file:file.store_string(JSON.stringify(report,"  "));file.close()
    print("MACOS_EXPORT_TESTS_DONE")
    get_tree().quit(1 if failed else 0)
