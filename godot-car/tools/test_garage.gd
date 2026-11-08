extends SceneTree
var failed := false
func check(ok: bool, description: String) -> void:
    print("PASS " if ok else "FAIL ",description)
    if not ok: failed = true
func _initialize():call_deferred("run")
func run():
    var path := "user://garage_test_%d.cfg"%Time.get_ticks_usec()
    var seed_config := ConfigFile.new()
    seed_config.set_value("garage","selected","classic")
    seed_config.set_value("race","best_time",91.0)
    seed_config.set_value("unrelated","keep",true)
    seed_config.save(path)
    var game = load("res://game.tscn").instantiate()
    game.profile_path = path
    root.add_child(game)
    current_scene = game
    for i in 4:await physics_frame
    check(game.state == game.RaceState.SELECTING and not game.car.enabled,"garage appears before countdown")
    check(game.selected_vehicle=="classic" and game.best_time==91.0,"legacy classic record and saved selection load")
    Input.action_press("accelerate")
    for i in 40:await physics_frame
    Input.action_release("accelerate")
    check(game.car.speed==0 and game.elapsed==0,"garage blocks driving and timer")
    game.tourer_button.pressed.emit()
    check(game.selected_vehicle=="tourer" and game.car.wheel_radius==.445,"Grand Tourer button swaps real model")
    check(game.car.visual.scene_file_path.ends_with("grand_tourer.glb"),"new car resource is installed")
    for i in 8:
        game.select_vehicle("classic")
        game.select_vehicle("tourer")
    await process_frame
    check(game.car.wheels.size()==4 and game.car.front_pivots.size()==2 and game.car.get_child_count()==2,"repeated swaps retain exactly one model and four wheels")
    game.classic_button.pressed.emit()
    check(game.selected_vehicle=="classic" and game.car.visual.scene_file_path.ends_with("car.glb"),"Classic button restores original model")
    var enter := InputEventAction.new()
    enter.action="restart_race"
    enter.pressed=true
    game._unhandled_input(enter)
    check(game.state==game.RaceState.COUNTDOWN and not game.garage_root.visible and game.hud_root.visible,"Enter starts chosen car countdown")
    game.elapsed=12.3
    game.finish_race()
    game.state=game.RaceState.SELECTING
    game.select_vehicle("tourer")
    check(game.best_time==0,"different cars have independent records")
    game.elapsed=19.2
    game.finish_race()
    var config := ConfigFile.new()
    config.load(path)
    check(is_equal_approx(float(config.get_value("race_classic","best_time")),12.3) and is_equal_approx(float(config.get_value("race_tourer","best_time")),19.2),"both car records persist independently")
    check(config.get_value("unrelated","keep")==true and config.get_value("race","best_time")==91.0,"record save preserves existing profile data")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    print("GARAGE_TESTS_DONE")
    quit(1 if failed else 0)
