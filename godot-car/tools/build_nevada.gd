extends SceneTree

# Run with: godot --headless --path . --script res://tools/build_nevada.gd
# The generator saves an editable scene; no generation is needed during play.
var world: Node3D
var rng := RandomNumberGenerator.new()
var sand: Material
var stone: Material
var sage: StandardMaterial3D
var wood: StandardMaterial3D
var asphalt: Material
var paint: Material
var yellow: Material
var mesh_index := 0
var erosion := FastNoiseLite.new()
var shrub_asset: PackedScene
var barrel_asset: PackedScene
var pear_asset: PackedScene

func surface(kind: int, texture_name: String, tint := Color.WHITE) -> ShaderMaterial:
    var mat := ShaderMaterial.new()
    mat.shader = load("res://materials/desert_surface.gdshader")
    mat.set_shader_parameter("surface_kind",kind)
    mat.set_shader_parameter("albedo_tex",load("res://textures/"+texture_name+"_albedo.png"))
    mat.set_shader_parameter("height_tex",load("res://textures/surface_height.png"))
    mat.set_shader_parameter("paint_color",tint)
    return mat

func plant_instance(asset: PackedScene, parent: Node, label: String, pos: Vector3, scale_value: float) -> void:
    var ob := asset.instantiate() as Node3D
    add_node(ob,parent,label)
    ob.position = pos
    ob.scale = Vector3.ONE*scale_value
    ob.rotation.y = rng.randf()*TAU

func material(color: Color) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = 0.93
    return m

func add_node(node: Node, parent: Node, label: String) -> Node:
    node.name = label
    parent.add_child(node)
    node.owner = world
    return node

func group(label: String) -> Node3D:
    return add_node(Node3D.new(), world, label) as Node3D

func mesh_node(mesh: Mesh, mat: Material, parent: Node, label: String, pos := Vector3.ZERO) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    node.mesh = mesh
    node.material_override = mat
    node.position = pos
    add_node(node, parent, label)
    return node

func box(parent: Node, label: String, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    return mesh_node(mesh, mat, parent, label, pos)

func cylinder(parent: Node, label: String, a: Vector3, b: Vector3, radius: float, mat: Material) -> MeshInstance3D:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = a.distance_to(b)
    mesh.radial_segments = 7
    mesh.rings = 1
    var node := mesh_node(mesh, mat, parent, label, (a+b)*0.5)
    var up := (b-a).normalized()
    var right := Vector3.FORWARD.cross(up).normalized()
    if right.length() < 0.1:
        right = Vector3.RIGHT
    node.basis = Basis(right, up, right.cross(up)).orthonormalized()
    return node

func terrain_height(x: float, z: float) -> float:
    var falloff := smoothstep(55.0, 110.0, absf(x))
    return -0.08 + falloff * (1.6 + sin(x*.024+z*.013)*1.8 + cos(z*.031-x*.017)*1.2)

func vertex(st: SurfaceTool, pos: Vector3, color: Color) -> void:
    st.set_color(color)
    st.add_vertex(pos)

func triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
    vertex(st,a,color)
    vertex(st,b,color)
    vertex(st,c,color)

func finish_mesh(st: SurfaceTool, label: String) -> ArrayMesh:
    st.generate_normals()
    var mesh := st.commit()
    var path := "res://world/" + label + ".res"
    assert(ResourceSaver.save(mesh,path) == OK)
    mesh.take_over_path(path)
    return mesh

func ground() -> void:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for iz in range(172):
        for ix in range(160):
            var x := -1600.0 + ix*20.0
            var z := -2600.0 + iz*20.0
            var a := Vector3(x,terrain_height(x,z),z)
            var b := Vector3(x+20,terrain_height(x+20,z),z)
            var c := Vector3(x,terrain_height(x,z+20),z+20)
            var d := Vector3(x+20,terrain_height(x+20,z+20),z+20)
            var shade := rng.randf_range(.92,1.05)
            var color := Color(.66,.47,.28)*shade
            triangle(st,a,b,c,color)
            triangle(st,b,d,c,color)
    var terrain := mesh_node(finish_mesh(st,"desert_terrain"),sand,world,"DesertTerrain")
    terrain.create_trimesh_collision()
    for body in terrain.get_children():
        body.owner = world
        for shape in body.get_children():shape.owner = world

func mountain(parent: Node, pos: Vector3, radius: float, height: float, index: int) -> void:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var steps := 48
    var points: Array[Vector3] = []
    for iz in range(steps+1):
        for ix in range(steps+1):
            var x := -1.0+2.0*ix/steps
            var z := -1.0+2.0*iz/steps
            var distortion := erosion.get_noise_2d((pos.x+x*radius)*1.5,(pos.z+z*radius)*1.5)
            var r := sqrt(x*x+z*z) * (1.0+distortion*.17)
            var top := smoothstep(1.0,.34,r)
            var ridges := erosion.get_noise_2d(pos.x+x*radius*3.0,pos.z+z*radius*3.0)
            var h := maxf(0.0,top*(.85+ridges*.18))*height
            points.append(Vector3(x*radius,h,z*radius*.78))
    for iz in steps:
        for ix in steps:
            var i := iz*(steps+1)+ix
            triangle(st,points[i],points[i+1],points[i+steps+1],Color.WHITE)
            triangle(st,points[i+1],points[i+steps+2],points[i+steps+1],Color.WHITE)
    st.index()
    mesh_node(finish_mesh(st,"mesa_%02d"%index),stone,parent,"ErodedRidge%02d"%index,pos)

func vegetation(parent: Node, pos: Vector3, size: float, index: int) -> void:
    plant_instance(shrub_asset,parent,"Sagebrush%03d"%index,pos,size)

func cactus(parent: Node, pos: Vector3, size: float, index: int) -> void:
    plant_instance(barrel_asset if index%2==0 else pear_asset,parent,"Cactus%03d"%index,pos,size)

func yucca(parent: Node, pos: Vector3, size: float, index: int) -> void:
    var root_node := Node3D.new()
    add_node(root_node,parent,"Yucca%03d"%index)
    root_node.position = pos
    cylinder(root_node,"Trunk",Vector3.ZERO,Vector3(0,size*.9,0),size*.07,wood)
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for j in 12:
        var angle := TAU*j/12.0
        var center := Vector3(0,size*.83,0)
        var side := Vector3(-sin(angle),0,cos(angle))*size*.065
        var tip := center + Vector3(cos(angle)*size*.62,size*rng.randf_range(.15,.48),sin(angle)*size*.62)
        triangle(st,center-side,tip,center+side,Color.WHITE)
    st.generate_normals()
    mesh_node(st.commit(),sage,root_node,"Leaves")

func welcome_sign(parent: Node, pos: Vector3) -> void:
    var root_node := Node3D.new()
    add_node(root_node,parent,"NevadaWelcomeSign")
    root_node.position = pos
    var green := material(Color(.055,.19,.16))
    for x in [-1.7,1.7]:
        cylinder(root_node,"Signpost",Vector3(x,0,0),Vector3(x,4.4,0),.065,wood)
    box(root_node,"WhiteBorder",Vector3(0,3.55,0),Vector3(4.7,2.2,.16),paint)
    box(root_node,"GreenPanel",Vector3(0,3.55,.1),Vector3(4.53,2.03,.05),green)
    var label := Label3D.new()
    label.text = "N E V A D A\nDESERT HIGHWAY\nNORTH  375"
    label.font_size = 64
    label.pixel_size = .007
    label.position = Vector3(0,3.55,.14)
    label.modulate = Color(.96,.91,.73)
    label.outline_size = 0
    add_node(label,root_node,"Lettering")

func _initialize() -> void:
    rng.seed = 3752026
    world = Node3D.new()
    world.name = "NevadaDesert"
    root.add_child(world)
    erosion.seed = 375
    erosion.frequency = .018
    shrub_asset = load("res://assets/sagebrush.glb")
    barrel_asset = load("res://assets/barrel_cactus.glb")
    pear_asset = load("res://assets/prickly_pear.glb")
    sand = surface(0,"sand")
    stone = surface(2,"rock")
    sage = material(Color(.28,.31,.19))
    sage.cull_mode = BaseMaterial3D.CULL_DISABLED
    wood = material(Color(.27,.18,.11))
    asphalt = surface(1,"asphalt")
    paint = surface(3,"asphalt",Color(.79,.77,.67))
    yellow = surface(3,"asphalt",Color(.76,.54,.14))
    ground()
    var road := group("Highway")
    box(road,"GravelShoulder",Vector3(0,-.015,-450),Vector3(12.6,.07,1100),sand)
    var road_mesh := box(road,"Asphalt",Vector3(0,.025,-450),Vector3(8.4,.06,1100),asphalt)
    road_mesh.create_trimesh_collision()
    for child in road_mesh.get_children():
        child.owner = world
        for sub in child.get_children():sub.owner = world
    for x in [-4.0,4.0]:
        box(road,"EdgeStripe",Vector3(x,.059,-450),Vector3(.12,.008,1100),paint)
    for x in [-.12,.12]:
        box(road,"CenterYellow",Vector3(x,.06,-450),Vector3(.085,.008,1100),yellow)
    var props := group("Roadside")
    for z in range(-980,81,40):
        for side in [-1,1]:
            box(props,"Delineator",Vector3(side*5.7,.48,z),Vector3(.1,.95,.1),paint)
            box(props,"Reflector",Vector3(side*5.7,.82,z+.058),Vector3(.11,.15,.025),yellow)
    var pole_mat := material(Color(.12,.11,.1))
    for i in 21:
        var z := 55.0-i*50
        cylinder(props,"UtilityPole",Vector3(17,0,z),Vector3(17,9,z),.12,wood)
        box(props,"Crossarm",Vector3(17,8.4,z),Vector3(3.6,.14,.16),wood)
        for x in [15.6,18.4]:
            cylinder(props,"Insulator",Vector3(x,8.4,z),Vector3(x,8.75,z),.09,paint)
            if i<20:
                for j in 8:
                    var t0 := j/8.0
                    var t1 := (j+1)/8.0
                    cylinder(props,"PowerLine",Vector3(x,8.75-sin(t0*PI)*1.15,z-t0*50),Vector3(x,8.75-sin(t1*PI)*1.15,z-t1*50),.018,pole_mat)
    welcome_sign(props,Vector3(9,0,7))
    var mountains := group("RockyMountains")
    for i in 30:
        var side := -1.0 if i%2==0 else 1.0
        var z := rng.randf_range(-1150,170)
        var radius := rng.randf_range(65,150)
        var x := side*rng.randf_range(150,620)
        mountain(mountains,Vector3(x,-2,z),radius,rng.randf_range(45,130),i)
    var plants := group("DesertPlants")
    var rocks := group("ScatteredRocks")
    var rock_mesh := SphereMesh.new()
    rock_mesh.radial_segments = 14
    rock_mesh.rings = 7
    rock_mesh.radius = 1
    rock_mesh.height = 1.5
    for i in 210:
        var side := -1.0 if i%2==0 else 1.0
        var x := side*rng.randf_range(8,110)
        var z := rng.randf_range(-950,85)
        var pos := Vector3(x,terrain_height(x,z),z)
        if i%5==0:
            cactus(plants,pos,rng.randf_range(.65,1.3),i)
        elif i%9==0:
            yucca(plants,pos,rng.randf_range(.8,1.5),i)
        else:
            vegetation(plants,pos,rng.randf_range(.6,1.7),i)
        var rp := Vector3(x+rng.randf_range(-2,2),pos.y,z+rng.randf_range(-3,3))
        var rock := mesh_node(rock_mesh,stone,rocks,"Rock%03d"%i,rp)
        var scale_value := rng.randf_range(.22,1.3)
        rock.scale = Vector3(scale_value*1.4,scale_value*.65,scale_value)
        rock.rotation.y = rng.randf()*TAU
    # Extra foreground vegetation gives the first stretch a readable sense of scale.
    for i in 34:
        var side := -1.0 if i%2==0 else 1.0
        var x := side*rng.randf_range(7.8,38)
        var z := rng.randf_range(-65,49)
        var pos := Vector3(x,terrain_height(x,z),z)
        if i%3==0:
            cactus(plants,pos,rng.randf_range(.7,1.4),300+i)
        else:
            vegetation(plants,pos,rng.randf_range(.9,1.7),300+i)
    var car := load("res://assets/car.glb").instantiate() as Node3D
    add_node(car,world,"Car")
    car.position = Vector3(2.05,.065,30)
    var sky_mat := ProceduralSkyMaterial.new()
    sky_mat.sky_top_color = Color(.12,.32,.51)
    sky_mat.sky_horizon_color = Color(.75,.76,.65)
    sky_mat.ground_bottom_color = Color(.4,.3,.21)
    sky_mat.ground_horizon_color = Color(.75,.76,.65)
    sky_mat.sky_curve = .16
    var sky := Sky.new()
    sky.sky_material = sky_mat
    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(.78,.83,.9)
    env.ambient_light_energy = .65
    env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    env.fog_enabled = true
    env.fog_light_color = Color(.67,.71,.72)
    env.fog_density = .0004
    env.fog_sky_affect = .2
    var environment := WorldEnvironment.new()
    environment.environment = env
    add_node(environment,world,"WorldEnvironment")
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-36,-35,0)
    sun.light_color = Color(1,.95,.86)
    sun.light_energy = .9
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 170
    add_node(sun,world,"AfternoonSun")
    var camera := Camera3D.new()
    camera.position = Vector3(10,5.5,42)
    camera.fov = 66
    camera.far = 4000
    add_node(camera,world,"Camera3D")
    camera.basis = Basis.looking_at(Vector3(1,1.5,12)-camera.position)
    camera.current = true
    var packed := PackedScene.new()
    assert(packed.pack(world)==OK)
    assert(ResourceSaver.save(packed,"res://nevada.tscn")==OK)
    print("NEVADA_BUILT: editable scene, 1100 m highway, 30 eroded ridges, 244 detailed plants, road and terrain collisions")
    quit()
