extends SceneTree
var game: Node
var failed := false
func check(ok: bool, description: String) -> void:
    print("PASS " if ok else "FAIL ", description)
    if not ok: failed = true
func frames(count: int) -> void:
    for i in count: await physics_frame
func _initialize():
    call_deferred("run")
func run():
    game = load("res://game.tscn").instantiate()
    game.save_records = false
    game.skip_selection = true
    game.selected_vehicle = "tourer" if "tourer" in OS.get_cmdline_user_args() else "classic"
    root.add_child(game)
    current_scene = game
    await frames(4)
    Input.action_press("accelerate")
    await frames(50)
    check(game.car.speed == 0, "countdown blocks acceleration")
    await frames(160)
    check(game.state == game.RaceState.RACING, "countdown starts race")
    await frames(270)
    check(game.car.speed > 25 and game.car.position.z < -35, "throttle moves vehicle on real road collider")
    check(game.car.is_on_floor(), "vehicle stays grounded")
    Input.action_press("steer_right")
    await frames(18)
    check(game.car.rotation.y < -0.02, "right input turns the vehicle right")
    check(game.car.front_pivots[0].rotation.y < 0, "front wheel steering animation")
    Input.action_release("steer_right")
    Input.action_release("accelerate")
    game.toggle_pause()
    var pos: Vector3 = game.car.position
    var time: float = game.elapsed
    for i in 12: await process_frame
    check(game.car.position.is_equal_approx(pos) and game.elapsed==time, "pause freezes car and race timer")
    game.toggle_pause()
    var penalty_before: float = game.elapsed
    game.recover()
    check(game.elapsed >= penalty_before+5 and game.recoveries==1 and game.car.speed==0, "recovery restores road position and adds penalty")
    Input.action_press("reverse")
    await frames(100)
    check(game.car.speed < -3 and game.car.position.z > 30, "reverse gear works")
    Input.action_release("reverse")
    game.car.reset_at(Vector3(2.05,.2,30))
    game.last_z = 30
    Input.action_press("accelerate")
    await frames(220)
    var braking_speed: float = game.car.speed
    Input.action_press("handbrake")
    await frames(80)
    check(absf(game.car.speed)<braking_speed*.5, "handbrake slows moving car")
    Input.action_release("handbrake")
    game.car.reset_at(Vector3(10,.2,20))
    game.last_z = 20
    await frames(200)
    check(game.car.speed<=12.01, "offroad speed limit")
    game.car.reset_at(Vector3(8,.2,-159))
    game.last_z = -159
    game.car.position.z = -161
    game._physics_process(1.0/60)
    check(game.next_gate==0, "driving outside checkpoint does not count")
    game.car.reset_at(Vector3(2.05,.2,30))
    game.last_z = 30
    for i in 2300:
        await physics_frame
        if game.state == game.RaceState.FINISHED: break
    Input.action_release("accelerate")
    check(game.state==game.RaceState.FINISHED and game.next_gate==5, "complete real physics drive through all four gates and finish")
    check(game.result_panel.visible and not game.car.enabled, "finish shows result and disables throttle")
    print("DRIVE_TESTS_DONE")
    quit(1 if failed else 0)
