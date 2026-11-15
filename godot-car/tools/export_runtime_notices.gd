extends SceneTree
## Collect the exact engine build's embedded license and third-party notices.
func _initialize()->void:
    var args:=OS.get_cmdline_user_args()
    if args.is_empty():
        push_error("Provide the notices output path")
        quit(1)
        return
    var file:=FileAccess.open(args[0],FileAccess.WRITE)
    if not file:
        push_error("Cannot write runtime notices")
        quit(1)
        return
    file.store_line("Godot Engine "+str(Engine.get_version_info().string))
    file.store_line("https://godotengine.org/license/")
    file.store_line(Engine.get_license_text())
    for component in Engine.get_copyright_info():
        file.store_line("\n"+str(component.name))
        for part in component.parts:
            for line in part.copyright:file.store_line(str(line))
            file.store_line("License: "+str(part.license))
    var licenses:Dictionary=Engine.get_license_info()
    var names:Array=licenses.keys()
    names.sort()
    for name in names:
        file.store_line("\n========== "+str(name)+" ==========\n")
        file.store_line(str(licenses[name]))
    file.close()
    print("RUNTIME_NOTICES_WRITTEN ",args[0])
    quit()
