extends Node
## Optional packaged-runtime verification, invoked only with --verify-export.
var checks:Array[Dictionary]=[]
var failed:=false
func check(ok:bool,label:String)->void:
    checks.append({"ok":ok,"check":label})
    if not ok:failed=true
    print("PASS " if ok else "FAIL ",label)
func run(game:Node)->void:
    check(OS.get_name()=="macOS" and OS.has_feature("arm64"),"native Apple Silicon runtime")
    check(not OS.has_feature("editor"),"export template runtime")
    check(FileAccess.file_exists("res://assets/pacific_city.json") and FileAccess.file_exists("res://assets/palm_bay.json"),"packed collision metadata")
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
    var report:={"ok":not failed,"engine":Engine.get_version_info().string,"checks":checks}
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--verify-report="):
            var file:=FileAccess.open(arg.trim_prefix("--verify-report="),FileAccess.WRITE)
            if file:file.store_string(JSON.stringify(report,"  "));file.close()
    print("MACOS_EXPORT_TESTS_DONE")
    get_tree().quit(1 if failed else 0)
