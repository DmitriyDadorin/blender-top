extends Node3D
## Night variant shares all city geometry and gameplay; only lighting is instance-local.
var positions:Array[Vector3]=[]
var local_lights:Array[OmniLight3D]=[]
var light_assignments:Array[int]=[]
var wanted_lamps:Array[int]=[]
var reassigned_lights:Array[int]=[]
var timer:=0.0
var world:Node3D

func setup(city:Node3D)->void:
    name="NightLighting"
    world=city
    var environment_node:WorldEnvironment=world.get_node("WorldEnvironment")
    var environment:=environment_node.environment.duplicate(true) as Environment
    environment_node.environment=environment
    var sky:=environment.sky.sky_material as ProceduralSkyMaterial
    sky.sky_top_color=Color(.008,.018,.05)
    sky.sky_horizon_color=Color(.045,.06,.10)
    sky.ground_bottom_color=Color(.005,.008,.015)
    sky.ground_horizon_color=Color(.025,.035,.06)
    environment.ambient_light_color=Color(.34,.45,.70)
    environment.ambient_light_energy=.19
    environment.fog_light_color=Color(.018,.027,.055)
    environment.fog_density=.00065
    environment.fog_sky_affect=.1
    var moon:DirectionalLight3D=world.get_node("Sun")
    moon.light_color=Color(.48,.61,1.0)
    moon.light_energy=.075
    moon.shadow_enabled=false
    for ob in world.find_children("*","MeshInstance3D",true,false):
        if ob.name!="StreetNetwork":ob.layers=3
    var foliage=world.get_node("Pedestrians")
    for ob in foliage.find_children("*","MeshInstance3D",true,false):ob.layers=3
    for ob in world.get_node("Horizon").find_children("DistantDistrict*","MultiMeshInstance3D",true,false):
        ob.material_override.set_shader_parameter("night_factor",1.0)
    world.get_node("Horizon/HarborFleet").set_night(true)
    configure_surfaces()
    create_lamps()
    for i in 4:
        var light:=OmniLight3D.new()
        light.name="NearbyStreetLight%d"%i
        light.light_color=Color(1,.69,.36)
        light.light_energy=0.0
        light.omni_range=23
        light.omni_attenuation=1.2
        light.light_cull_mask=2
        light.shadow_enabled=false
        add_child(light)
        local_lights.append(light)
        light_assignments.append(-1)
    update_lights()

func configure_surfaces()->void:
    var surfaces:Dictionary={}
    for ob in world.find_children("*","MeshInstance3D",true,false):
        if ob.name=="StreetNetwork" or ob.name.begins_with("Block_"):
            for index in ob.mesh.get_surface_count():
                var original:=ob.mesh.surface_get_material(index) as StandardMaterial3D
                if not original:continue
                var title:=original.resource_name
                if title.begins_with("City_Asphalt") or title.begins_with("City_Road white") or title.begins_with("City_Road yellow") or title.begins_with("City_Concrete") or title.begins_with("City_Pale stone"):
                    if not surfaces.has(title):
                        var surface:=ShaderMaterial.new()
                        surface.shader=load("res://materials/night_surface.gdshader")
                        surface.set_shader_parameter("base_color",original.albedo_color)
                        surface.set_shader_parameter("use_texture",original.albedo_texture!=null)
                        if original.albedo_texture:surface.set_shader_parameter("surface_texture",original.albedo_texture)
                        surface.set_shader_parameter("coastal_cutoff",title.begins_with("City_Asphalt"))
                        surfaces[title]=surface
                    ob.set_surface_override_material(index,surfaces[title])
        if ob.name in ["PACIFIC CITY","SUNSET BLVD","DOWNTOWN","GRAND AVENUE","PACIFIC HOTEL","COFFEE"]:
            for index in ob.mesh.get_surface_count():
                var sign:=ob.mesh.surface_get_material(index).duplicate() as StandardMaterial3D
                sign.emission_enabled=true
                sign.emission=Color(1,.64,.24)
                sign.emission_energy_multiplier=.7
                ob.set_surface_override_material(index,sign)

func batch(label:String,mesh:Mesh,material:Material,transforms:Array[Transform3D])->void:
    var multi:=MultiMesh.new()
    multi.transform_format=MultiMesh.TRANSFORM_3D
    multi.mesh=mesh
    multi.instance_count=transforms.size()
    for i in transforms.size():multi.set_instance_transform(i,transforms[i])
    var node:=MultiMeshInstance3D.new()
    node.name=label
    node.multimesh=multi
    node.material_override=material
    node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(node)

func create_lamps()->void:
    var heads:Array[Transform3D]=[]
    var poles:Array[Transform3D]=[]
    var arms:Array[Transform3D]=[]
    for axis in [-480,-320,-160,0,160,320,480]:
        for coord in range(-420,470,40):
            for side in [-1,1]:
                for horizontal in [false,true]:
                    var position:=Vector3(coord,8.18,axis+side*6.2) if horizontal else Vector3(axis+side*6.2,8.18,coord)
                    positions.append(position)
                    heads.append(Transform3D(Basis.from_scale(Vector3(.85,.055,.32) if not horizontal else Vector3(.32,.055,.85)),position))
                    if horizontal:
                        poles.append(Transform3D(Basis.from_scale(Vector3(.16,8,.16)),Vector3(coord,4.1,axis+side*8.5)))
                        arms.append(Transform3D(Basis.from_scale(Vector3(.12,.12,2.4)),Vector3(coord,8.2,axis+side*7.3)))
                    elif (coord+420)%80!=0:
                        poles.append(Transform3D(Basis.from_scale(Vector3(.16,8,.16)),Vector3(axis+side*8.5,4.1,coord)))
                        arms.append(Transform3D(Basis.from_scale(Vector3(2.4,.12,.12)),Vector3(axis+side*7.3,8.2,coord)))
    var glow:=StandardMaterial3D.new()
    glow.albedo_color=Color(1,.83,.5)
    glow.emission_enabled=true
    glow.emission=Color(1,.62,.24)
    glow.emission_energy_multiplier=2.2
    glow.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
    var metal:=StandardMaterial3D.new()
    metal.albedo_color=Color(.04,.05,.06)
    metal.metallic=.5
    metal.roughness=.55
    var cube:=BoxMesh.new()
    batch("LampLenses",cube,glow,heads)
    batch("NightLampPoles",cube,metal,poles)
    batch("NightLampArms",cube,metal,arms)

func update_lights()->void:
    var camera:=get_viewport().get_camera_3d()
    var car:=world.get_node_or_null("PlayerCar") as Node3D
    var target:=world.to_local(car.global_position if car else camera.global_position if camera else Vector3(2.5,0,420))
    var ranked:Array[int]=[]
    var scores:Dictionary={}
    for i in positions.size():
        ranked.append(i)
        # Keep a current lamp through small distance ties at junctions.
        scores[i]=positions[i].distance_to(target)-(3.0 if i in light_assignments else 0.0)
    ranked.sort_custom(func(a:int,b:int):return a<b if is_equal_approx(float(scores[a]),float(scores[b])) else scores[a]<scores[b])
    wanted_lamps.clear()
    for i in local_lights.size():wanted_lamps.append(ranked[i])

func assign_dark_lights()->void:
    for i in local_lights.size():
        var light:=local_lights[i]
        if light_assignments[i] in wanted_lamps or light.light_energy>0:continue
        for candidate in wanted_lamps:
            if candidate in light_assignments:continue
            light.position=positions[candidate]-Vector3(0,.5,0)
            light_assignments[i]=candidate
            reassigned_lights.append(i)
            break

func _process(delta:float)->void:
    timer+=delta
    if timer>.1:
        timer=0
        update_lights()
    # Retain each physical lamp's slot. Recycle it only after a full dark frame,
    # then fade the new location in instead of teleporting an illuminated light.
    assign_dark_lights()
    for i in local_lights.size():
        if i in reassigned_lights:continue
        var desired:=5.0 if light_assignments[i] in wanted_lamps else 0.0
        var rate:=12.0 if desired>0 else 18.0
        local_lights[i].light_energy=move_toward(local_lights[i].light_energy,desired,delta*rate)
    reassigned_lights.clear()
