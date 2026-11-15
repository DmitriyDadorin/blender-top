extends Node
## Vehicle and environment loops stay phase-continuous; controls only change their mix.
const ENGINE_TRIM_DB:=2.0
const AMBIENCE_TRIM_DB:=-5.0
var game:Node
var loops:Dictionary={}
var gains:Dictionary={}
var rpm:=850.0
var gear:=1
var tyre_slip:=0.0
var muted:=false
var levels:Dictionary={"master":.75,"vehicle":.8,"ambience":.75}
var save_delay:=-1.0
var last_state:=-1
var last_handbrake:=false
var horn_cooldown:=0.0
var distant_timer:=25.0
var ignition:AudioStreamPlayer
var horn:AudioStreamPlayer
var handbrake_click:AudioStreamPlayer
var distant_horn:AudioStreamPlayer3D
var engine_filter:AudioEffectLowPassFilter
var rng:=RandomNumberGenerator.new()

func setup(owner_game:Node)->void:
    name="GameAudio"
    process_mode=Node.PROCESS_MODE_ALWAYS
    game=owner_game
    rng.seed=82314
    for title in ["DriveMaster","DriveVehicle","DriveAmbience","DriveEngine"]:
        if AudioServer.get_bus_index(title)<0:
            AudioServer.add_bus()
            AudioServer.set_bus_name(AudioServer.bus_count-1,title)
        var destination:="DriveVehicle" if title=="DriveEngine" else "Master" if title=="DriveMaster" else "DriveMaster"
        AudioServer.set_bus_send(AudioServer.get_bus_index(title),destination)
    var engine_bus:=AudioServer.get_bus_index("DriveEngine")
    AudioServer.set_bus_volume_db(engine_bus,ENGINE_TRIM_DB)
    if AudioServer.get_bus_effect_count(engine_bus)==0:
        var filter:=AudioEffectLowPassFilter.new()
        filter.cutoff_hz=1500
        filter.resonance=.5
        filter.db=AudioEffectFilter.FILTER_24DB
        AudioServer.add_bus_effect(engine_bus,filter)
    engine_filter=AudioServer.get_bus_effect(engine_bus,0) as AudioEffectLowPassFilter
    var master:=AudioServer.get_bus_index("DriveMaster")
    if AudioServer.get_bus_effect_count(master)==0:
        var limiter:=AudioEffectHardLimiter.new()
        limiter.ceiling_db=-.5
        AudioServer.add_bus_effect(master,limiter)
    var config:=ConfigFile.new()
    if config.load(game.profile_path)==OK:
        for key in levels:levels[key]=clampf(float(config.get_value("audio",key,levels[key])),0,1)
        muted=bool(config.get_value("audio","muted",false))
    apply_levels()
    for key in ["engine_idle","engine_load","road_roll","tyre_skid","city_traffic","ocean_waves","wind"]:
        var bus:="DriveEngine" if key in ["engine_idle","engine_load"] else "DriveVehicle" if key in ["road_roll","tyre_skid"] else "DriveAmbience"
        var player:=make_player(key,bus,true)
        player.volume_db=-80
        loops[key]=player
        gains[key]=0.0
        player.play()
    ignition=make_player("engine_start","DriveEngine",false)
    ignition.volume_db=-10
    horn=make_player("horn","DriveVehicle",false)
    horn.volume_db=-8
    handbrake_click=make_player("handbrake","DriveVehicle",false)
    handbrake_click.volume_db=-22
    distant_horn=AudioStreamPlayer3D.new()
    distant_horn.name="DistantCityHorn"
    distant_horn.stream=load("res://audio/horn.wav")
    distant_horn.bus="DriveAmbience"
    distant_horn.volume_db=-10
    distant_horn.unit_size=15
    distant_horn.max_distance=220
    distant_horn.process_mode=Node.PROCESS_MODE_PAUSABLE
    add_child(distant_horn)
    last_state=game.state

func make_player(key:String,bus:String,looped:bool)->AudioStreamPlayer:
    var player:=AudioStreamPlayer.new()
    player.name=key.to_pascal_case()
    var stream:=load("res://audio/"+key+".wav").duplicate() as AudioStreamWAV
    if looped:
        stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
        stream.loop_begin=0
        stream.loop_end=roundi(stream.get_length()*stream.mix_rate)
    player.stream=stream
    player.bus=bus
    player.process_mode=Node.PROCESS_MODE_PAUSABLE
    add_child(player)
    return player

func apply_levels()->void:
    for key in levels:
        var title:String={"master":"DriveMaster","vehicle":"DriveVehicle","ambience":"DriveAmbience"}[key]
        var index:=AudioServer.get_bus_index(title)
        var trim_db:=AMBIENCE_TRIM_DB if key=="ambience" else 0.0
        AudioServer.set_bus_volume_db(index,linear_to_db(maxf(.0001,float(levels[key])))+trim_db)
        AudioServer.set_bus_mute(index,(muted if key=="master" else false) or float(levels[key])<=.001)

func set_volume(category:String,value:float)->void:
    levels[category]=clampf(value,0,1)
    apply_levels()
    save_delay=.4

func set_muted(value:bool)->void:
    muted=value
    apply_levels()
    save_delay=.4

func save_settings()->void:
    save_delay=-1
    if not game.save_records:return
    var config:=ConfigFile.new()
    config.load(game.profile_path)
    for key in levels:config.set_value("audio",key,levels[key])
    config.set_value("audio","muted",muted)
    config.save(game.profile_path)

func honk()->void:
    if horn_cooldown>0 or not game.car.enabled or get_tree().paused:return
    horn.pitch_scale=.92 if game.selected_vehicle=="classic" else 1.05
    horn.play()
    horn_cooldown=.7

func mix_drive(speed:float,steering:float,gas:float,brake:float,handbrake:bool,grounded:bool,enabled:bool,offroad:bool,delta:float)->void:
    var velocity:=absf(speed)
    var shifts:Array[float]=[7,13,21,29]
    if speed<-.2:gear=1
    else:
        while gear<5 and velocity>shifts[gear-1]+.5:gear+=1
        while gear>1 and velocity<shifts[gear-2]-.8:gear-=1
    var ratios:Array[float]=[3.0,2.0,1.4,1.05,.82]
    var target_rpm:=clampf(850+velocity*ratios[gear-1]*180+gas*500,850,5900) if enabled else 850.0
    rpm=lerpf(rpm,target_rpm,1.0-exp(-delta*8))
    # Both layers come from the same real V8 exhaust take. Match their playback
    # rates so the body and throttle detail keep one coherent engine note.
    var revs:=smoothstep(850,5700,rpm)
    var voice:=.97 if game.selected_vehicle=="classic" else .90
    var pitch:float=lerpf(.86,1.62,revs)*voice
    loops.engine_idle.pitch_scale=pitch
    loops.engine_load.pitch_scale=pitch
    var cutoff:=lerpf(1350,2250,revs)*lerpf(.86,1.0,gas)
    engine_filter.cutoff_hz=lerpf(engine_filter.cutoff_hz,cutoff,1.0-exp(-delta*5))
    # Road noise should add a faint low texture, without sweeping up into hiss.
    loops.road_roll.pitch_scale=clampf(.92+velocity/250,.92,1.06)*(.9 if offroad else 1.0)
    var angle:=absf(steering)*.43/(1+velocity*.045)
    var lateral:=velocity*velocity*tan(angle)/2.7
    # Normal cornering stays quiet. Squeal requires braking while cornering
    # above ~54 km/h, or a deliberate handbrake skid on the road.
    var corner:=smoothstep(.25,.65,absf(steering))*smoothstep(4,9,lateral)
    tyre_slip=smoothstep(15,23,velocity)*corner*smoothstep(.15,.65,brake)
    if handbrake:tyre_slip=maxf(tyre_slip,smoothstep(6,14,velocity)*maxf(corner,.55))
    if not grounded or not enabled or offroad:tyre_slip=0
    loops.tyre_skid.pitch_scale=.9+velocity/180+tyre_slip*.1
    var ignition_duck:=.35 if ignition.playing else 1.0
    mix_gain("engine_idle",(.23-revs*.10)*ignition_duck,delta)
    mix_gain("engine_load",(.035+gas*.32+revs*.06)*ignition_duck if enabled else 0.0,delta)
    mix_gain("road_roll",smoothstep(2,32,velocity)*(.14 if offroad else .085) if grounded else 0.0,delta,2.5)
    mix_gain("tyre_skid",tyre_slip*.38,delta,11.0)

func mix_gain(key:String,target:float,delta:float,rate:float=5.0)->void:
    gains[key]=lerpf(float(gains[key]),target,1.0-exp(-delta*rate))
    loops[key].volume_db=linear_to_db(maxf(.0001,float(gains[key])))

func _process(delta:float)->void:
    if not is_instance_valid(game) or not is_instance_valid(game.car):return
    if save_delay>=0:
        save_delay-=delta
        if save_delay<=0:save_settings()
    if get_tree().paused:return
    horn_cooldown=maxf(0,horn_cooldown-delta)
    if last_state!=game.state:
        if game.state==game.RaceState.COUNTDOWN:ignition.play()
        last_state=game.state
    var car=game.car
    var forward_gas:=Input.get_action_strength("accelerate") if car.enabled else 0.0
    var reverse_gas:=Input.get_action_strength("reverse") if car.enabled else 0.0
    var gas:=forward_gas if car.speed>.2 else (reverse_gas if car.speed<-.2 else maxf(forward_gas,reverse_gas))
    var brake:=reverse_gas if car.speed>.2 else forward_gas if car.speed<-.2 else 0.0
    var handbrake:bool=car.enabled and Input.is_action_pressed("handbrake")
    if handbrake and not last_handbrake:handbrake_click.play()
    last_handbrake=handbrake
    mix_drive(car.speed,car.steering,gas,brake,handbrake,car.is_on_floor(),car.enabled,car.is_offroad(),delta)
    var city:bool=game.is_city_map()
    var resort:bool=game.selected_map=="palm_bay"
    var coast:float=1-smoothstep(30,200 if resort else 320,absf(car.position.x+(386 if resort else 520))) if city or resort else 0.0
    var garage:=.65 if game.state==game.RaceState.SELECTING else 1.0
    var night:bool=game.selected_map=="city_night"
    mix_gain("city_traffic",(.28 if night else .46)*(1-coast*.35)*garage if city else .055*garage if resort else 0.0,delta,.9)
    mix_gain("ocean_waves",coast*(.32 if resort else .45)*garage,delta,.9)
    var wind_speed:=smoothstep(12,34,absf(car.speed))
    mix_gain("wind",.004+wind_speed*.018 if city or resort else .018+wind_speed*.025,delta,1.5)
    if city:
        distant_timer-=delta
        if distant_timer<0:
            distant_timer=rng.randf_range(28,55)
            distant_horn.position=car.position+Vector3(rng.randf_range(-90,90),1,rng.randf_range(-110,-60))
            distant_horn.pitch_scale=rng.randf_range(.8,1.05)
            distant_horn.play()
    elif distant_horn.playing:distant_horn.stop()

func _exit_tree()->void:
    if is_instance_valid(game) and save_delay>=0:save_settings()
    for player in get_children():
        if player is AudioStreamPlayer or player is AudioStreamPlayer3D:
            player.stop()
            player.stream=null
    loops.clear()
