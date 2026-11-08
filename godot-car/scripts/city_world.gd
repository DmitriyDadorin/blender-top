extends Node3D

@export var night_mode:=false

const PLAY_LIMIT := 510.0
const WARNING_START := 493.0

static func outside_play_area(pos: Vector3) -> bool:
    return absf(pos.x)>PLAY_LIMIT or absf(pos.z)>PLAY_LIMIT

static func near_boundary(pos: Vector3) -> bool:
    return absf(pos.x)>WARNING_START or absf(pos.z)>WARNING_START


var clock := 0.0
var signal_heads: Array = []
var bulb_materials: Array[StandardMaterial3D] = []
var metadata: Dictionary

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_PAUSABLE
    metadata = JSON.parse_string(FileAccess.get_file_as_string("res://assets/pacific_city.json"))
    # Reflective glass stays in the wall's single opaque pass: no duplicate panes.
    var glass_shader:Shader=load("res://materials/city_glass_facade.gdshader")
    var mask:Texture2D=load("res://textures/city_window_mask.png")
    var reflection_prefix:="city_night_reflection_" if night_mode and ResourceLoader.exists("res://textures/city_night_reflection_north.png") else "city_reflection_"
    var reflection_exposure:=.06 if night_mode and reflection_prefix=="city_reflection_" else 1.0
    var glass_materials:Dictionary={}
    for ob in find_children("Block_*","MeshInstance3D",true,false):
        for index in ob.mesh.get_surface_count():
            var facade := ob.mesh.surface_get_material(index) as StandardMaterial3D
            if facade and facade.resource_name.begins_with("City_Baked"):
                facade.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
                if not glass_materials.has(facade.resource_name):
                    var glass:=ShaderMaterial.new()
                    glass.shader=glass_shader
                    glass.set_shader_parameter("facade_albedo",facade.albedo_texture)
                    glass.set_shader_parameter("window_mask",mask)
                    glass.set_shader_parameter("window_data",load("res://textures/city_window_data.png"))
                    glass.set_shader_parameter("reflection_north",load("res://textures/"+reflection_prefix+"north.png"))
                    glass.set_shader_parameter("reflection_south",load("res://textures/"+reflection_prefix+"south.png"))
                    glass.set_shader_parameter("night_factor",1.0 if night_mode else 0.0)
                    glass.set_shader_parameter("reflection_exposure",reflection_exposure)
                    glass_materials[facade.resource_name]=glass
                ob.set_surface_override_material(index,glass_materials[facade.resource_name])
    var vehicle_glass:=ShaderMaterial.new()
    vehicle_glass.shader=load("res://materials/city_car_glass.gdshader")
    vehicle_glass.set_shader_parameter("reflection_north",load("res://textures/"+reflection_prefix+"north.png"))
    vehicle_glass.set_shader_parameter("reflection_south",load("res://textures/"+reflection_prefix+"south.png"))
    vehicle_glass.set_shader_parameter("reflection_exposure",reflection_exposure)
    for ob in find_children("Enriched_ParkedCars*","MeshInstance3D",true,false):
        for index in ob.mesh.get_surface_count():
            var original:=ob.mesh.surface_get_material(index) as StandardMaterial3D
            if original and original.resource_name.begins_with("City_Car glazing"):
                ob.set_surface_override_material(index,vehicle_glass)
    var foliage_materials:Dictionary={}
    for ob in find_children("Enriched_Landscaping*","MeshInstance3D",true,false):
        for index in ob.mesh.get_surface_count():
            var original:=ob.mesh.surface_get_material(index) as StandardMaterial3D
            if original and original.resource_name.begins_with("City_Broadleaf "):
                if not foliage_materials.has(original.resource_name):
                    var leaves:=ShaderMaterial.new()
                    leaves.shader=load("res://materials/city_foliage.gdshader")
                    leaves.set_shader_parameter("leaf_color",original.albedo_color)
                    foliage_materials[original.resource_name]=leaves
                ob.set_surface_override_material(index,foliage_materials[original.resource_name])
    var collisions := Node3D.new()
    collisions.name = "CityCollisions"
    add_child(collisions)
    for entry in metadata.colliders:
        var body := StaticBody3D.new()
        var shape := BoxShape3D.new()
        shape.size = Vector3(entry.size[0],entry.size[1],entry.size[2])
        var collision := CollisionShape3D.new()
        collision.shape = shape
        body.position = Vector3(entry.position[0],entry.position[1],entry.position[2])
        body.add_child(collision)
        collisions.add_child(body)
    for color in [Color(.95,.025,.008),Color(1,.59,.015),Color(.03,.85,.18)]:
        for active in [false,true]:
            var material := StandardMaterial3D.new()
            material.albedo_color = color if active else color*.09
            material.emission_enabled = active
            material.emission = color
            material.emission_energy_multiplier = .8
            material.roughness = .35
            bulb_materials.append(material)
    var mesh := SphereMesh.new()
    mesh.radius = .12
    mesh.height = .24
    mesh.radial_segments = 10
    mesh.rings = 4
    var signals := Node3D.new()
    signals.name = "TrafficSignals"
    add_child(signals)
    for entry in metadata.signals:
        var head: Array[MeshInstance3D] = []
        for i in 3:
            var bulb := MeshInstance3D.new()
            bulb.mesh = mesh
            bulb.position = Vector3(entry.position[0]-entry.direction[0]*.18,entry.position[1]+.30-i*.30,entry.position[2]-entry.direction[2]*.18)
            bulb.visibility_range_end = 240
            bulb.visibility_range_end_margin = 25
            bulb.material_override = bulb_materials[i*2]
            signals.add_child(bulb)
            head.append(bulb)
        signal_heads.append({"bulbs":head,"axis":entry.axis,"offset":entry.offset,"last":-1})
    update_signals()
    var pedestrians:=Node3D.new()
    pedestrians.set_script(load("res://scripts/city_life.gd"))
    add_child(pedestrians)
    if night_mode:
        var night:=Node3D.new()
        night.set_script(load("res://scripts/night_city.gd"))
        add_child(night)
        night.setup(self)

func light_state(axis: int, offset: float = 0.0) -> int:
    var phase := fmod(clock+offset,36.0)
    if axis==0:
        if phase<14: return 2
        if phase<17: return 1
    else:
        if phase>=18 and phase<32: return 2
        if phase>=32 and phase<35: return 1
    return 0

func update_signals() -> void:
    for head in signal_heads:
        var active := light_state(head.axis,head.offset)
        if active==head.last: continue
        head.last = active
        for i in 3:
            head.bulbs[i].material_override = bulb_materials[i*2+(1 if i==active else 0)]

func _process(delta: float) -> void:
    clock += delta
    update_signals()
