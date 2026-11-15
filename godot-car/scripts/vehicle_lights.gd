extends Node3D
## Lens shading and real lamps share one state; this rig belongs to the car model.
var car:CharacterBody3D
var headlamps:Array[SpotLight3D]=[]
var brake_spill:Array[SpotLight3D]=[]
var reverse_lamps:Array[MeshInstance3D]=[]
var lens_materials:Array[ShaderMaterial]=[]
var headlights_on:=false
var braking:=false
var reversing:=false
var sample_timer:=0.0
var dark_timer:=0.0
var rear_positions:Array[Vector3]=[]

func setup(model:Node3D,vehicle:CharacterBody3D) -> void:
    car=vehicle
    name="VehicleLights"
    var front_points:Array[Vector3]=[]
    var rear_points:Array[Vector3]=[]
    for ob in model.find_children("*","MeshInstance3D",true,false):
        var to_model:Transform3D=model.global_transform.affine_inverse()*ob.global_transform
        for index in ob.mesh.get_surface_count():
            var original:=ob.mesh.surface_get_material(index) as StandardMaterial3D
            if not original:continue
            var label:=original.resource_name.to_lower()
            var head:bool=label=="gt_headlight" or label=="фары"
            var tail:bool=label=="gt_tail lens" or label=="задние фонари"
            if not head and not tail:continue
            var shader:=ShaderMaterial.new()
            shader.shader=load("res://materials/vehicle_lens.gdshader")
            shader.set_shader_parameter("part_to_vehicle",to_model)
            shader.set_shader_parameter("lens_color",original.albedo_color)
            shader.set_shader_parameter("rear_lens",tail)
            ob.set_surface_override_material(index,shader)
            lens_materials.append(shader)
            var vertices:PackedVector3Array=ob.mesh.surface_get_arrays(index)[Mesh.ARRAY_VERTEX]
            for vertex in vertices:
                var p:=to_model*vertex
                if head and p.z<-.5 and absf(p.x)>.3:front_points.append(p)
                if tail:rear_points.append(p)
    for side in [-1.0,1.0]:
        var front:=lamp_center(front_points,side,Vector3(side*.61,.8,-2.2))
        var rear:=lamp_center(rear_points,side,Vector3(side*.6,.9,2.25))
        rear_positions.append(rear)
        var lamp:=SpotLight3D.new()
        lamp.name="LowBeamLeft" if side<0 else "LowBeamRight"
        lamp.position=front+Vector3(0,0,-.045)
        lamp.rotation_degrees.x=-4.5
        lamp.spot_angle=28
        lamp.spot_range=64
        lamp.spot_attenuation=.6
        lamp.spot_angle_attenuation=1.2
        lamp.light_color=Color(1.0,.94,.82)
        lamp.light_energy=10.0
        lamp.shadow_enabled=true
        lamp.shadow_bias=.02
        lamp.shadow_normal_bias=.4
        add_child(lamp)
        headlamps.append(lamp)
        # Tail lamps cast light behind the car, rather than an omnidirectional
        # red wash back onto the boot, doors and rear window.
        var spill:=SpotLight3D.new()
        spill.name="BrakeSpillLeft" if side<0 else "BrakeSpillRight"
        spill.position=rear+Vector3(0,-.13,.14)
        spill.rotation_degrees=Vector3(-30,180,0)
        spill.light_color=Color(1,.012,.004)
        spill.spot_range=3.2
        spill.spot_angle=40
        spill.spot_attenuation=1.4
        spill.spot_angle_attenuation=1.5
        spill.light_energy=0.0
        spill.shadow_enabled=false
        spill.light_specular=0.0
        add_child(spill)
        brake_spill.append(spill)
        var white:=StandardMaterial3D.new()
        white.albedo_color=Color(.22,.23,.21)
        white.emission_enabled=true
        white.emission=Color(.9,.94,1)
        white.emission_energy_multiplier=0.0
        var mesh:=BoxMesh.new()
        mesh.size=Vector3(.09,.045,.013)
        var backup:=MeshInstance3D.new()
        backup.name="ReverseLamp"
        backup.mesh=mesh
        backup.material_override=white
        backup.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        backup.position=rear+Vector3(-side*.12,-.095,.05)
        add_child(backup)
        reverse_lamps.append(backup)
    evaluate_darkness(0,true)
    set_driver_state(false,false)

func lamp_center(points:Array[Vector3],side:float,fallback:Vector3)->Vector3:
    var sum:=Vector3.ZERO
    var count:=0
    for p in points:
        if p.x*side>0:sum+=p;count+=1
    return sum/count if count>0 else fallback

func environmental_brightness()->float:
    if not is_instance_valid(car):return 1.0
    var environment:Environment=get_world_3d().environment
    var brightness:float=environment.ambient_light_energy if environment else .5
    var world:=car.get_parent()
    var sun:=world.get_node_or_null("Sun") as DirectionalLight3D
    if not sun:sun=world.get_node_or_null("AfternoonSun") as DirectionalLight3D
    if sun and sun.is_visible_in_tree():brightness+=sun.light_energy
    return brightness

func evaluate_darkness(delta:float,immediate:bool=false)->void:
    var level:=environmental_brightness()
    var desired:=level<(.42 if headlights_on else .30)
    if immediate:
        headlights_on=desired
        dark_timer=0
        update_outputs()
    elif desired!=headlights_on:
        dark_timer+=delta
        if dark_timer>=.7:
            headlights_on=desired
            dark_timer=0
            update_outputs()
    else:dark_timer=0

func set_driver_state(brake:bool,reverse:bool)->void:
    if brake==braking and reverse==reversing:return
    braking=brake
    reversing=reverse
    update_outputs()

func update_outputs()->void:
    for lamp in headlamps:lamp.visible=headlights_on
    # Compatibility compiles a new lit shader when a spotlight first becomes
    # visible. Keep these short-range, shadowless lights paired with geometry
    # from the garage onward; braking only changes their energy, not the shader.
    for spill in brake_spill:spill.light_energy=.8 if braking else 0.0
    # The reverse lens also exists while unlit. Enabling its glow must not
    # introduce a new emissive material on the first change into reverse.
    for lamp in reverse_lamps:
        var material:=lamp.material_override as StandardMaterial3D
        material.albedo_color=Color(.85,.86,.8) if reversing else Color(.22,.23,.21)
        material.emission_energy_multiplier=1.2 if reversing else 0.0
    for lens in lens_materials:
        lens.set_shader_parameter("head_energy",3.0 if headlights_on else 0.0)
        lens.set_shader_parameter("tail_energy",.42 if headlights_on else 0.0)
        lens.set_shader_parameter("brake_energy",3.8 if braking else 0.0)

func _process(delta:float)->void:
    sample_timer+=delta
    if sample_timer>=.15:
        evaluate_darkness(sample_timer)
        sample_timer=0
