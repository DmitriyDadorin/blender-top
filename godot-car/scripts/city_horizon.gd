@tool
extends Node3D

const PROMENADE_LAND_EDGE_X := -495.0
const PROMENADE_WIDTH := 20.0
const Bounds = preload("res://scripts/city_world.gd")
var building_count := 0

func plain_material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color=color
    material.roughness=.95
    return material

func mesh_node(label: String, mesh: Mesh, material: Material, pos: Vector3) -> MeshInstance3D:
    var ob := MeshInstance3D.new()
    ob.name=label
    ob.mesh=mesh
    ob.material_override=material
    ob.position=pos
    ob.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(ob)
    return ob

func box(label: String, pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
    var mesh:=BoxMesh.new()
    mesh.size=size
    return mesh_node(label,mesh,material,pos)

func _ready() -> void:
    build_skyline()
    build_coast()
    build_exit_markers()
    var fleet:=Node3D.new()
    fleet.set_script(load("res://scripts/harbor_fleet.gd"))
    add_child(fleet)
    fleet.build()

func build_skyline() -> void:
    var rng:=RandomNumberGenerator.new()
    rng.seed=443711
    # Shared meshes and one batch per district keep the distant city inexpensive.
    var mesh:=BoxMesh.new()
    mesh.size=Vector3.ONE
    var material:=ShaderMaterial.new()
    material.shader=load("res://materials/city_skyline.gdshader")
    var groups:Dictionary={}
    for ix in range(-3,31):
        for iz in range(-31,31):
            var center:=Vector3(80+ix*160,0,80+iz*160)
            if absf(center.x)<490 and absf(center.z)<490:continue
            var key:=Vector2i(floori(center.x/960),floori(center.z/960))
            if not groups.has(key):groups[key]=[]
            for dx in [-34.0,34.0]:
                for dz in [-34.0,34.0]:
                    var height:=rng.randf_range(15,65)
                    if rng.randf()<.12:height=rng.randf_range(75,170)
                    var size:=Vector3(rng.randf_range(29,51),height,rng.randf_range(30,52))
                    var pos:=center+Vector3(dx,height*.5,dz)
                    var color:=Color(.36,.40,.42).lerp(Color(.58,.56,.49),rng.randf())
                    groups[key].append({"transform":Transform3D(Basis.from_scale(size),pos),"color":color})
                    building_count+=1
    var group_index:=0
    for key in groups:
        var entries:Array=groups[key]
        var multi:=MultiMesh.new()
        multi.transform_format=MultiMesh.TRANSFORM_3D
        multi.use_colors=true
        multi.mesh=mesh
        multi.instance_count=entries.size()
        for i in entries.size():
            multi.set_instance_transform(i,entries[i].transform)
            multi.set_instance_color(i,entries[i].color)
        var ob:=MultiMeshInstance3D.new()
        ob.name="DistantDistrict%02d"%group_index
        ob.multimesh=multi
        ob.material_override=material
        ob.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        add_child(ob)
        group_index+=1
    # The extended land hides the original square base while fog blends its far edge.
    box("DistantLand",Vector3(3742.5,-.22,0),Vector3(8515,.3,16000),plain_material(Color(.26,.28,.27)))
    # Distant boulevards continue the foreground street grid.
    var road:=plain_material(Color(.12,.14,.15))
    for axis in range(-30,32):
        var coord:=axis*160.0
        if coord>=-480:
            box("FarAvenue",Vector3(coord,-.055,0),Vector3(14,.02,10200),road)
        if absf(coord)>=640:
            box("FarBoulevard",Vector3(2250,-.055,coord),Vector3(5500,.02,14),road)

func build_coast() -> void:
    # End the imported asphalt before the promenade begins. Both tops are at
    # y=0.055, so keeping asphalt underneath causes depth fighting across the strip.
    var street := get_parent().find_child("StreetNetwork",true,false) as MeshInstance3D
    if street:
        var clipped := ShaderMaterial.new()
        clipped.shader=load("res://materials/coastal_asphalt.gdshader")
        clipped.set_shader_parameter("coast_cutoff",PROMENADE_LAND_EDGE_X)
        clipped.set_shader_parameter("asphalt_tex",load("res://assets/pacific_city_asphalt_albedo.png"))
        for index in street.mesh.get_surface_count():
            var original := street.mesh.surface_get_material(index)
            if original and original.resource_name.begins_with("City_Asphalt"):
                street.set_surface_override_material(index,clipped)
    var sea:=PlaneMesh.new()
    sea.size=Vector2(48000,48000)
    sea.subdivide_width=24
    sea.subdivide_depth=24
    var water:=ShaderMaterial.new()
    water.shader=load("res://materials/pacific_ocean.gdshader")
    mesh_node("Ocean",sea,water,Vector3(-24530,-.45,0))
    var surface:=SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for v in [Vector3(-515,.055,-24000),Vector3(-550,-.72,-24000),Vector3(-515,.055,24000),Vector3(-550,-.72,-24000),Vector3(-550,-.72,24000),Vector3(-515,.055,24000)]:
        surface.add_vertex(v)
    surface.generate_normals()
    var beach_material:=plain_material(Color(.56,.49,.36))
    beach_material.cull_mode=BaseMaterial3D.CULL_DISABLED
    mesh_node("Beach",surface.commit(),beach_material,Vector3.ZERO)
    box("CoastalPromenade",Vector3(PROMENADE_LAND_EDGE_X-PROMENADE_WIDTH*.5,.025,0),Vector3(PROMENADE_WIDTH,.06,16000),plain_material(Color(.42,.43,.40)))
    var rail:=plain_material(Color(.17,.20,.21))
    box("SeafrontRailing",Vector3(-514,.85,0),Vector3(.08,.07,10200),rail)
    for z in range(-650,651,16):
        box("RailingPost",Vector3(-514,.42,z),Vector3(.08,.85,.08),rail)

func build_exit_markers() -> void:
    var amber:=plain_material(Color(.85,.49,.08))
    var dark:=plain_material(Color(.08,.10,.11))
    var edge:=Bounds.PLAY_LIMIT-10.0
    var marker_index:=0
    for axis in [-480,-320,-160,0,160,320,480]:
        for direction in [Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT]:
            var pos:Vector3=direction*edge
            var right:Vector3=direction.cross(Vector3.UP)
            pos+=right*axis
            var frame:=Node3D.new()
            frame.name="ExitMarker_%02d"%marker_index
            marker_index+=1
            frame.position=pos
            frame.rotation.y=atan2(-direction.x,-direction.z)
            add_child(frame)
            # A painted line and small roadside board mark the return area, not a wall.
            for x in range(-6,7,2):
                var stripe:=MeshInstance3D.new()
                var mesh:=BoxMesh.new()
                mesh.size=Vector3(1.25,.008,.35)
                stripe.mesh=mesh
                stripe.material_override=amber
                stripe.position=Vector3(x,.066,0)
                frame.add_child(stripe)
            for x in [7.9,9.9]:
                var pole:=MeshInstance3D.new()
                var mesh:=BoxMesh.new()
                mesh.size=Vector3(.06,2.4,.06)
                pole.mesh=mesh
                pole.material_override=dark
                pole.position=Vector3(x,1.2,0)
                frame.add_child(pole)
            var board:=MeshInstance3D.new()
            var panel:=BoxMesh.new()
            panel.size=Vector3(2.5,1.15,.10)
            board.mesh=panel
            board.material_override=dark
            board.position=Vector3(8.9,2.05,0)
            frame.add_child(board)
            var label:=Label3D.new()
            label.text="КРАЙ ЗОНЫ\nВОЗВРАТ К ТОЧКЕ"
            label.font_size=52
            label.pixel_size=.0035
            label.outline_size=0
            label.modulate=Color(1,.75,.3)
            label.position=Vector3(8.9,2.05,.065)
            label.visibility_range_end=150
            frame.add_child(label)
