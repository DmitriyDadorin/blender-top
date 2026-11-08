extends SceneTree
var failed:=false
func check(ok:bool,label:String):
    print("PASS " if ok else "FAIL ",label)
    if not ok:failed=true
func _initialize():call_deferred("run")
func run():
    Engine.max_fps=60
    var profile:="user://audio_test_%d.cfg"%Time.get_ticks_usec()
    var config:=ConfigFile.new()
    config.set_value("garage","map","city")
    config.set_value("race_tourer","best_time",19.0)
    config.save(profile)
    var game=load("res://game.tscn").instantiate()
    game.profile_path=profile
    game.save_records=false
    root.add_child(game)
    current_scene=game
    var audio=game.audio_director
    var fleet=game.get_node("World/Horizon/HarborFleet")
    check(fleet.boats.size()==14,"coast has eight yachts and six large vessels")
    var vessels_safe:=true
    var mesh_surfaces:=0
    var positions:Array[Vector3]=[]
    for boat in fleet.boats:
        positions.append(boat.node.position)
        if boat.node.position.x> -575:vessels_safe=false
        mesh_surfaces+=boat.node.mesh.get_surface_count()
    check(vessels_safe,"all vessels sit on water outside the driving area")
    check(mesh_surfaces<180,"vessel details use bounded material batches")
    check(not fleet.night_mode and not fleet.cabin_material.emission_enabled,"day boats keep their lights off")
    for i in 4:await process_frame
    for i in positions.size():check(fleet.boats[i].node.position.is_equal_approx(positions[i]),"anchored vessel keeps its position")
    var voices:int=audio.get_child_count()
    for key in audio.loops:
        var stream:AudioStreamWAV=audio.loops[key].stream
        check(stream.get_length()>.5 and stream.loop_mode==AudioStreamWAV.LOOP_FORWARD and stream.loop_end>1000,key+" has a real looped audio buffer")
    audio.set_process(false)
    audio.mix_drive(0,1,0,0,false,true,true,false,1)
    check(audio.tyre_slip==0,"parking steering does not squeal")
    audio.mix_drive(22,0,1,0,false,true,true,false,1)
    var cruise_rpm:float=audio.rpm
    check(cruise_rpm>2000 and audio.gear>1,"speed raises engine RPM and engages driving gears")
    check(audio.loops.engine_load.stream.get_length()>7 and audio.loops.engine_idle.stream.get_length()>7,"engine uses the replacement long V8 exhaust take")
    check(audio.loops.engine_load.pitch_scale<1.65 and is_equal_approx(audio.loops.engine_idle.pitch_scale,audio.loops.engine_load.pitch_scale),"engine layers retain one coherent low exhaust note")
    var engine_bus:=AudioServer.get_bus_index("DriveEngine")
    check(audio.loops.engine_load.bus=="DriveEngine" and AudioServer.get_bus_send(engine_bus)=="DriveVehicle","engine filtering preserves the vehicle volume control")
    check(audio.engine_filter.cutoff_hz<2300 and audio.engine_filter.db==AudioEffectFilter.FILTER_24DB,"post-pitch engine filter softens high-frequency whine")
    var loaded_gain:float=audio.gains.engine_load
    var loaded_cutoff:float=audio.engine_filter.cutoff_hz
    audio.mix_drive(22,0,0,0,false,true,true,false,1)
    check(float(audio.gains.engine_load)<loaded_gain*.5 and audio.engine_filter.cutoff_hz<loaded_cutoff,"lifting the throttle softens the engine tone and load")
    check(audio.tyre_slip==0,"straight cruising has rolling sound without a tyre squeal")
    audio.mix_drive(34,0,1,0,false,true,true,false,2)
    check(float(audio.gains.road_roll)<float(audio.gains.engine_load)*.25 and audio.loops.road_roll.pitch_scale<1.08,"maximum-speed road texture stays quiet without a high-pitched sweep")
    audio.mix_drive(22,1,1,0,false,true,true,false,1)
    check(audio.tyre_slip==0 and float(audio.gains.tyre_skid)<.001,"even a fast corner stays quiet without braking")
    audio.mix_drive(22,1,0,1,false,true,true,false,1)
    check(audio.tyre_slip>.7 and float(audio.gains.tyre_skid)>.2,"braking into a fast corner produces tyre squeal")
    audio.mix_drive(12,1,0,1,false,true,true,false,1)
    check(audio.tyre_slip==0,"slow corner with braking stays quiet")
    audio.mix_drive(22,0,0,1,false,true,true,false,1)
    check(audio.tyre_slip==0,"straight braking does not trigger corner squeal")
    audio.mix_drive(22,1,0,1,false,true,true,true,1)
    check(audio.tyre_slip==0,"leaving the asphalt suppresses asphalt tyre squeal")
    audio.mix_drive(12,0,0,0,true,true,true,false,1)
    check(audio.tyre_slip>.4,"deliberate handbrake slide still produces skid sound")
    audio.mix_drive(22,1,1,0,true,false,true,false,1)
    check(audio.tyre_slip==0,"airborne wheels do not squeal against the road")
    audio.mix_drive(0,0,0,0,false,true,false,false,1)
    check(audio.rpm<1000,"engine returns smoothly to idle when stopped")
    game.car.position.x=2.5
    audio._process(8)
    var inland:float=audio.gains.ocean_waves
    game.car.speed=34
    audio._process(3)
    check(float(audio.gains.wind)<.025,"city wind remains a faint background at maximum speed")
    game.car.speed=0
    game.car.position.x=-480
    audio._process(8)
    check(float(audio.gains.ocean_waves)>inland+.25,"wave ambience grows near the coast")
    game.select_map("city_night")
    var night_fleet=game.get_node("World/Horizon/HarborFleet")
    check(night_fleet.night_mode and night_fleet.cabin_material.emission_enabled,"night map lights cabin panes and navigation markers")
    check(game.get_node("World/Horizon/Ocean").material_override.get_shader_parameter("harbor_night")==1.0,"ship lights reflect on night water")
    check(game.audio_director==audio and audio.get_child_count()==voices,"map swaps reuse one audio director")
    game.select_map("city")
    check(not game.get_node("World/Horizon/HarborFleet").night_mode,"daylight restores unlit vessels")
    game.select_map("desert")
    audio._process(10)
    check(float(audio.gains.city_traffic)<.002 and float(audio.gains.ocean_waves)<.002,"desert does not retain city or sea ambience")
    audio.set_muted(true)
    check(AudioServer.is_bus_mute(AudioServer.get_bus_index("DriveMaster")),"mute silences the game master bus")
    audio.set_muted(false)
    audio.set_volume("vehicle",.42)
    game.save_records=true
    audio.save_settings()
    config.load(profile)
    check(is_equal_approx(float(config.get_value("audio","vehicle")),.42) and config.get_value("race_tourer","best_time")==19.0,"volume settings preserve race records")
    audio.set_process(true)
    for i in 5:await process_frame
    paused=true
    for i in 4:await process_frame
    check(audio.loops.engine_idle.stream_paused,"pause suspends engine playback")
    paused=false
    for i in 4:await process_frame
    check(not audio.loops.engine_idle.stream_paused,"resume restores audio playback")
    game.queue_free()
    await process_frame
    await process_frame
    DirAccess.remove_absolute(ProjectSettings.globalize_path(profile))
    print("FLEET_AUDIO_TESTS_DONE")
    quit(1 if failed else 0)
