extends SceneTree
## Run with --windowed and a graphical renderer to verify aspect ratios and menus.
func _initialize():call_deferred("run")
func run():
    var game=load("res://game.tscn").instantiate()
    game.save_records=false
    game.profile_path="user://_display_visual_check.cfg"
    game.selected_map="palm_bay"
    root.add_child(game)
    current_scene=game
    var checker=load("res://scripts/export_self_test.gd").new()
    root.add_child(checker)
    await checker.verify_display(game)
    checker.finish()
