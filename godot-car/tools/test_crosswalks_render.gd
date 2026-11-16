extends SceneTree
## Pixel regression for visible, evenly shaded crosswalks. Run with graphics.
func _initialize():call_deferred("run")
func run():
    var game=load("res://game.tscn").instantiate()
    game.save_records=false
    game.profile_path="user://_crosswalk_visual_check.cfg"
    game.selected_map="city"
    root.add_child(game)
    current_scene=game
    var checker=load("res://scripts/export_self_test.gd").new()
    root.add_child(checker)
    await checker.verify_crosswalks(game)
    checker.finish()
