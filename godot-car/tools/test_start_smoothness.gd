extends SceneTree
# Run with a real renderer: godot --fixed-fps 144 --path . --script res://tools/test_start_smoothness.gd
# Screen-space second differences detect 60 Hz stepping on faster displays.
class RenderProbe extends Node:
    signal sampled
    func _process(_delta: float) -> void: sampled.emit()

func _initialize():call_deferred("run")
func run():
    var game=load("res://game.tscn").instantiate()
    game.save_records=false
    game.skip_selection=true
    game.selected_vehicle = "classic" if "classic" in OS.get_cmdline_user_args() else "tourer"
    root.add_child(game)
    current_scene=game
    game.countdown=.01
    Input.action_press("accelerate")
    var probe := RenderProbe.new()
    probe.process_priority = 100
    root.add_child(probe)
    var positions:Array[Vector2]=[]
    for i in 330:
        await probe.sampled
        if i>=30:
            var t:Transform3D=game.car.global_transform
            if ProjectSettings.get_setting("physics/common/physics_interpolation",false):
                t=game.car.get_global_transform_interpolated()
            positions.append(game.camera.unproject_position(t.origin+Vector3(0,1,0)))
    var peak=0.0
    var total=0.0
    for i in range(2,positions.size()):
        var acc=(positions[i]-2*positions[i-1]+positions[i-2]).length()
        peak=maxf(peak,acc)
        total+=acc
    print("SCREEN_JITTER mean=",total/(positions.size()-2)," peak=",peak," px/frame^2; fps=144 physics=60")
    Input.action_release("accelerate")
    var mean_jitter: float = total/(positions.size()-2)
    var smooth: bool = mean_jitter<0.05 and peak<0.15
    print("PASS smooth rendered launch" if smooth else "FAIL visible physics stepping")
    game.recover()
    var reset_pose: Transform3D = game.car.get_camera_target_transform()
    var reset_ok := reset_pose.origin.distance_to(game.car.global_position)<0.001
    print("PASS recovery resets interpolation" if reset_ok else "FAIL recovery render pose trails teleport")
    quit(0 if smooth and reset_ok else 1)
