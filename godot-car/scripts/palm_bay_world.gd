@tool
extends Node3D
## Original seaside resort: broad color fields, modernist volumes, quiet water.
const PLAY_LIMIT:=350.0
const WARNING_START:=337.0
const START:=Vector3(-317.5,.2,240)
const ROUTE:Array[Vector3]=[
    Vector3(-317.5,0,240),Vector3(-317.5,0,-317.5),
    Vector3(317.5,0,-317.5),Vector3(317.5,0,317.5),
    Vector3(-157.5,0,317.5),Vector3(-157.5,0,162.5),
    Vector3(162.5,0,162.5),Vector3(162.5,0,-162.5),
    Vector3(-2.5,0,-162.5),Vector3(-2.5,0,80)]
@export var use_exported_model:=true
var materials:Dictionary={}
var batches:Dictionary={}
var collisions:Node3D
var geometry:Node3D
var rng:=RandomNumberGenerator.new()
var cube:BoxMesh
var cylinder:CylinderMesh
var sphere:SphereMesh
var plane:PlaneMesh
var placement:=Transform3D.IDENTITY
var palm_count:=0
var building_count:=0
var pool_count:=0

static func outside_play_area(pos:Vector3)->bool:
    return absf(pos.x)>PLAY_LIMIT or absf(pos.z)>PLAY_LIMIT
static func near_boundary(pos:Vector3)->bool:
    return absf(pos.x)>WARNING_START or absf(pos.z)>WARNING_START

func _ready()->void:
    if get_node_or_null("ArtGeometry"):return
    if use_exported_model and ResourceLoader.exists("res://assets/palm_bay.glb") and FileAccess.file_exists("res://assets/palm_bay.json"):
        load_blender_scene()
        return
    rng.seed=198507
    geometry=Node3D.new()
    geometry.name="ArtGeometry"
    add_child(geometry)
    collisions=Node3D.new()
    collisions.name="PalmCollisions"
    add_child(collisions)
    cube=BoxMesh.new()
    cube.size=Vector3.ONE
    cylinder=CylinderMesh.new()
    cylinder.top_radius=.44
    cylinder.bottom_radius=.5
    cylinder.height=1
    cylinder.radial_segments=10
    sphere=SphereMesh.new()
    sphere.radius=.5
    sphere.height=1
    sphere.radial_segments=20
    sphere.rings=10
    plane=PlaneMesh.new()
    plane.size=Vector2.ONE
    palette()
    landscape()
    roads()
    resort()
    neighborhoods()
    promenade()
    marina()
    finish_batches()
    if use_exported_model:configure_art_surfaces()

func load_blender_scene()->void:
    geometry=load("res://assets/palm_bay.glb").instantiate()
    geometry.name="ArtGeometry"
    add_child(geometry)
    var metadata:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/palm_bay.json"))
    palm_count=int(metadata.palm_count)
    building_count=int(metadata.building_count)
    pool_count=int(metadata.pool_count)
    collisions=Node3D.new()
    collisions.name="PalmCollisions"
    add_child(collisions)
    for entry in metadata.colliders:
        var body:=StaticBody3D.new()
        body.position=Vector3(entry.position[0],entry.position[1],entry.position[2])
        body.rotation.y=float(entry.yaw)
        var shape:=BoxShape3D.new()
        shape.size=Vector3(entry.size[0],entry.size[1],entry.size[2])
        var collider:=CollisionShape3D.new()
        collider.shape=shape
        body.add_child(collider)
        collisions.add_child(body)
    configure_art_surfaces()

func configure_art_surfaces()->void:
    var overrides:Dictionary={}
    for ob in geometry.find_children("*","MeshInstance3D",true,false):
        for index in ob.mesh.get_surface_count():
            var original:=ob.mesh.surface_get_material(index) as StandardMaterial3D
            if not original:continue
            var title:=original.resource_name
            var road:=title.begins_with("PalmBay_road")
            var sea:=title.begins_with("PalmBay_ocean")
            var grass:=title.begins_with("PalmBay_grass")
            var sand:=title.begins_with("PalmBay_sand")
            if not (road or sea or grass or sand):continue
            if not overrides.has(title):
                var mat:=ShaderMaterial.new()
                mat.shader=load("res://materials/palm_bay_road.gdshader" if road else "res://materials/palm_bay_horizon.gdshader")
                mat.set_shader_parameter("base_color",original.albedo_color)
                if not road:mat.set_shader_parameter("sea_surface",sea)
                overrides[title]=mat
            ob.set_surface_override_material(index,overrides[title])

func color_material(key:String,color:Color,unshaded:bool=false)->void:
    var material:=StandardMaterial3D.new()
    material.resource_name="PalmBay_"+key
    material.albedo_color=color
    material.roughness=.94
    material.metallic_specular=.08
    if unshaded:material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
    if key in ["leaf","sail","cloth"]:material.cull_mode=BaseMaterial3D.CULL_DISABLED
    materials[key]=material

func palette()->void:
    color_material("white",Color(.95,.90,.79))
    color_material("coral",Color(.96,.31,.24))
    color_material("pink",Color(.95,.56,.51))
    color_material("navy",Color(.025,.13,.24))
    color_material("road",Color(.075,.12,.19))
    color_material("walk",Color(.79,.60,.49))
    color_material("grass",Color(.055,.32,.19))
    color_material("leaf",Color(.012,.23,.14))
    color_material("hedge",Color(.026,.27,.18))
    color_material("trunk",Color(.67,.49,.31))
    color_material("sand",Color(.96,.88,.73))
    color_material("yellow",Color(.98,.81,.43))
    color_material("aqua",Color(.13,.67,.70))
    color_material("pool",Color(.012,.43,.65),true)
    color_material("ocean",Color(.025,.22,.43),true)
    color_material("island",Color(.19,.32,.57),true)
    color_material("sail",Color(.98,.96,.86))
    color_material("cloth",Color(.94,.46,.42))
    color_material("flowers",Color(.81,.08,.26))

func append_mesh(mesh:Mesh,transform:Transform3D,key:String)->void:
    if not batches.has(key):
        var tool:=SurfaceTool.new()
        tool.begin(Mesh.PRIMITIVE_TRIANGLES)
        batches[key]=tool
    batches[key].append_from(mesh,0,transform)

func box(pos:Vector3,size:Vector3,key:String,solid:bool=false,yaw:float=0)->void:
    var basis:=Basis(Vector3.UP,yaw).scaled(size)
    append_mesh(cube,placement*Transform3D(basis,pos),key)
    if solid:collision_box(pos,size,yaw)

func collision_box(pos:Vector3,size:Vector3,yaw:float=0)->void:
    var body:=StaticBody3D.new()
    body.transform=placement*Transform3D(Basis(Vector3.UP,yaw),pos)
    var shape:=BoxShape3D.new()
    shape.size=size
    var collision:=CollisionShape3D.new()
    collision.shape=shape
    body.add_child(collision)
    collisions.add_child(body)

func ground_rect(x0:float,x1:float,z0:float,z1:float,key:String)->void:
    append_mesh(plane,Transform3D(Basis.from_scale(Vector3(x1-x0,1,z1-z0)),Vector3((x0+x1)*.5,0,(z0+z1)*.5)),key)

func oval(pos:Vector3,size:Vector3,key:String)->void:
    append_mesh(sphere,placement*Transform3D(Basis.from_scale(size),pos),key)

func beam(a:Vector3,b:Vector3,width:float,key:String)->void:
    var basis:=Basis(Quaternion(Vector3.UP,(b-a).normalized())).scaled(Vector3(width,a.distance_to(b),width))
    append_mesh(cylinder,placement*Transform3D(basis,(a+b)*.5),key)

func triangle(key:String,a:Vector3,b:Vector3,c:Vector3,normal:Vector3)->void:
    if not batches.has(key):
        var tool:=SurfaceTool.new()
        tool.begin(Mesh.PRIMITIVE_TRIANGLES)
        batches[key]=tool
    var tool:SurfaceTool=batches[key]
    for vertex in [a,b,c]:
        tool.set_normal(placement.basis*normal)
        tool.set_uv(Vector2.ZERO)
        tool.add_vertex(placement*vertex)

func finish_batches()->void:
    for key in batches:
        var ob:=MeshInstance3D.new()
        ob.name=String(key).capitalize()+"Geometry"
        ob.mesh=batches[key].commit()
        ob.material_override=materials[key]
        if key in ["ocean","pool","island"]:ob.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        geometry.add_child(ob)
    batches.clear()

func landscape()->void:
    # Foreground cells, shore and background share edges, never stacked faces.
    ground_rect(376,6000,-6000,6000,"grass")
    ground_rect(-386,376,376,6000,"grass")
    ground_rect(-386,376,-6000,-376,"grass")
    ground_rect(-386,-376,-376,376,"sand")
    ground_rect(-10386,-386,-10000,10000,"ocean")
    collision_box(Vector3(7.5,-.11,0),Vector3(745,.22,760))
    # Long, low silhouettes leave a wide clear ocean horizon.
    for i in 3:
        oval(Vector3(-1550-i*450,-5,-900+i*760),Vector3(650,85+i*20,220),"island")
    for x in [-377.0,377.0]:box(Vector3(x,.5,0),Vector3(.6,1,760),"pink")
    for z in [-377.0,377.0]:box(Vector3(0,.5,z),Vector3(755,1,.6),"pink")

func roads()->void:
    var cuts:Array[float]=[-376,-350,376]
    for axis in [-320.0,-160.0,0.0,160.0,320.0]:
        for offset in [-12.5,-7.0,7.0,12.5]:cuts.append(axis+offset)
    cuts.sort()
    for ix in cuts.size()-1:
        for iz in cuts.size()-1:
            var x:float=(cuts[ix]+cuts[ix+1])*.5
            var z:float=(cuts[iz]+cuts[iz+1])*.5
            var dx:=absf(x-roundf(x/160)*160)
            var dz:=absf(z-roundf(z/160)*160)
            var key:="road" if minf(dx,dz)<7 else "walk" if minf(dx,dz)<12.5 else "sand" if x< -350 else "grass"
            ground_rect(cuts[ix],cuts[ix+1],cuts[iz],cuts[iz+1],key)

func sign_text(text:String,pos:Vector3,yaw:float,size:float=1.0)->void:
    var label:=Label3D.new()
    label.text=text
    label.font_size=80
    label.pixel_size=.027*size
    label.modulate=Color(.99,.96,.86)
    label.outline_size=0
    label.transform=placement*Transform3D(Basis(Vector3.UP,yaw),pos)
    geometry.add_child(label)

func palm(pos:Vector3,height:float=10,yaw:float=0)->void:
    palm_count+=1
    var crown:=pos+Vector3(cos(yaw)*.65,height,sin(yaw)*.65)
    var last:=pos
    for i in 5:
        var t:=float(i+1)/5
        var next:=pos+Vector3(cos(yaw)*.65*t*t,height*t,sin(yaw)*.65*t*t)
        beam(last,next,.42-t*.14,"trunk")
        last=next
    for leaf in 13:
        var angle:=yaw+float(leaf)*TAU/13
        var outward:=Vector3(cos(angle),0,sin(angle))
        var side:=Vector3(-sin(angle),0,cos(angle))
        var length:=4.8+sin(leaf*2.17)*.8
        for segment in 9:
            var t0:=float(segment)/9
            var t1:=float(segment+1)/9
            var c0:=crown+outward*length*t0+Vector3.UP*(sin(t0*PI)*1.8-t0*t0*2.3)
            var c1:=crown+outward*length*t1+Vector3.UP*(sin(t1*PI)*1.8-t1*t1*2.3)
            var w0:=sin(t0*PI)*.58
            var w1:=sin(t1*PI)*.58
            var normal:=(Vector3.UP+side*.18).normalized()
            triangle("leaf",c0-side*w0,c1-side*w1,c1,normal)
            triangle("leaf",c0-side*w0,c1,c0,normal)
            normal=(Vector3.UP-side*.18).normalized()
            triangle("leaf",c0,c1,c1+side*w1,normal)
            triangle("leaf",c0,c1+side*w1,c0+side*w0,normal)

func pool(center:Vector3,size:Vector2)->void:
    pool_count+=1
    box(center+Vector3(0,.12,0),Vector3(size.x+8,.24,size.y+8),"white")
    box(center+Vector3(0,.26,0),Vector3(size.x,.035,size.y),"pool")
    for x in [-size.x*.5,size.x*.5]:box(center+Vector3(x,.30,0),Vector3(.3,.12,size.y+.6),"white")
    for z in [-size.y*.5,size.y*.5]:box(center+Vector3(0,.30,z),Vector3(size.x,.12,.3),"white")
    # A few broad lane marks read as clean graphic shapes through still water.
    for z in [-size.y*.23,size.y*.23]:box(center+Vector3(0,.281,z),Vector3(size.x*.8,.008,.16),"aqua")

func parasol(pos:Vector3,coral:bool=true)->void:
    beam(pos,pos+Vector3(0,3.2,0),.075,"white")
    for i in 16:
        var a:=TAU*i/16
        var b:=TAU*(i+1)/16
        var center:=pos+Vector3(0,3.4,0)
        var p:=pos+Vector3(cos(a)*2.1,2.8,sin(a)*2.1)
        var q:=pos+Vector3(cos(b)*2.1,2.8,sin(b)*2.1)
        triangle("cloth" if coral and i%2==0 else "sail",center,q,p,Vector3.UP)

func lounger(pos:Vector3)->void:
    box(pos+Vector3(0,.34,0),Vector3(1.0,.15,2.3),"white")
    box(pos+Vector3(0,.44,.15),Vector3(.83,.08,1.7),"coral")
    for x in [-.37,.37]:
        beam(pos+Vector3(x,.1,-.9),pos+Vector3(x,.38,.9),.055,"white")

func resort()->void:
    # Flagship hotel faces the sea across a large quiet pool terrace.
    building_count+=1
    box(Vector3(-202,6.5,240),Vector3(29,13,111),"white",true)
    box(Vector3(-202,13.2,240),Vector3(34,.5,116),"white")
    box(Vector3(-218,1.1,240),Vector3(1.2,2.2,114),"coral")
    for floor in 3:
        var y:=3.0+floor*3.7
        box(Vector3(-216.58,y,240),Vector3(.12,2.4,101),"navy")
        box(Vector3(-219,y-1.35,240),Vector3(6,.3,112),"white")
        box(Vector3(-221.8,y-.9,240),Vector3(.18,.65,112),"white")
        for z in range(190,295,10):box(Vector3(-217,y,z),Vector3(.9,2.5,.3),"white")
    sign_text("PALM BAY",Vector3(-218,14.8,240),-PI*.5,1.1)
    pool(Vector3(-275,0,239),Vector2(48,64))
    for rect in [Rect2(-307,182,4,116),Rect2(-247,182,28,116),Rect2(-303,182,56,21),Rect2(-303,275,56,23)]:
        box(Vector3(rect.position.x+rect.size.x*.5,.12,rect.position.y+rect.size.y*.5),Vector3(rect.size.x,.24,rect.size.y),"white")
    for z in range(213,272,11):
        lounger(Vector3(-301,0,z))
        if z%2==1:parasol(Vector3(-305,0,z),true)
    for z in [198.0,221.0,259.0,282.0]:
        parasol(Vector3(-231,.24,z),true)
        oval(Vector3(-231,1.05,z),Vector3(2.2,.18,2.2),"white")
        for side in [-1.0,1.0]:
            box(Vector3(-231+side*1.6,.7,z),Vector3(.9,.18,.9),"coral")
            box(Vector3(-231+side*1.95,1.2,z),Vector3(.15,1.0,.9),"white")
    for z in [190.0,289.0]:
        for x in [-292.0,-234.0]:palm(Vector3(x,0,z),11.5,rng.randf()*TAU)
    box(Vector3(-262,.55,297),Vector3(75,1.1,.7),"pink",true)
    # Low diner pavilion and its striped canopy.
    building_count+=1
    box(Vector3(-245,3.2,-242),Vector3(95,6.4,44),"white",true)
    box(Vector3(-245,3.3,-219.8),Vector3(85,3.8,.18),"navy")
    box(Vector3(-245,6.6,-214),Vector3(104,.55,17),"coral")
    for x in range(-287,-198,9):box(Vector3(x,3.2,-209),Vector3(.2,6.4,.2),"white")
    sign_text("SUMMER CLUB",Vector3(-245,8.7,-219.5),0,1.2)
    pool(Vector3(-244,0,-278),Vector2(62,17))
    for x in [-288.0,-200.0]:palm(Vector3(x,0,-190),12,rng.randf()*TAU)
    for i in 5:parked_car(Vector3(-282+i*18,0,-190),0,["white","aqua","coral"][i%3])

func villa(center:Vector3,accent:String,has_pool:bool,yaw:float=0)->void:
    building_count+=1
    var previous:=placement
    placement=Transform3D(Basis(Vector3.UP,yaw),center)
    var height:=rng.randf_range(4.8,7.0)
    box(Vector3(0,height*.5,0),Vector3(40,height,18),"white",true)
    box(Vector3(-11,height+.95,0),Vector3(16,1.9,18),accent)
    box(Vector3(0,height+.15,0),Vector3(44,.35,22),"white")
    box(Vector3(0,height*.48,9.12),Vector3(35,height*.61,.18),"navy")
    for x in [-17.0,-5.7,5.7,17.0]:box(Vector3(x,height*.48,9.3),Vector3(.24,height*.67,.32),"white")
    box(Vector3(-23,.45,6),Vector3(.5,.9,43),accent,true)
    for i in 8:box(Vector3(20.7+i*.75,.16+i*.29,1),Vector3(.85,.29,6),"white")
    if has_pool:pool(Vector3(0,0,18),Vector2(29,12))
    else:box(Vector3(0,.1,18),Vector3(37,.2,20),"walk")
    # Open front terraces put the water a few metres behind the sidewalk.
    for z in [14.0,22.0]:lounger(Vector3(-18.2,0,z))
    parasol(Vector3(-18.3,0,18),true)
    oval(Vector3(-18.3,.85,18),Vector3(1.2,.12,1.2),"white")
    for z in [12.0,25.0]:
        box(Vector3(20.5,.35,z),Vector3(2.1,.7,2.1),accent)
        oval(Vector3(20.5,1.02,z),Vector3(2.3,1.0,2.3),"hedge")
        for dx in [-.65,.65]:oval(Vector3(20.5+dx,1.55,z),Vector3(.8,.65,.8),"flowers")
    # A low carport, its parked coupe, rooftop pergola and street-facing address.
    box(Vector3(28,3.0,-1),Vector3(11,.3,17),"white")
    for x in [23.3,32.7]:
        for z in [-8.0,6.0]:box(Vector3(x,1.4,z),Vector3(.22,2.8,.22),"white")
    parked_car(Vector3(28,0,-.5),0,"coral" if building_count%3==0 else "aqua")
    for x in [-16.0,-7.0]:
        box(Vector3(x,height+1.6,-1),Vector3(.22,2.8,.22),"white")
    for i in 7:box(Vector3(-11.5,height+3.1,-4+i),Vector3(12,.24,.32),"white")
    box(Vector3(-20.5,1.2,27.5),Vector3(2.9,1.6,.32),accent)
    sign_text("%02d"%building_count,Vector3(-20.5,1.25,27.7),0,.36)
    palm(Vector3(-27,0,22),rng.randf_range(8.5,11),rng.randf()*TAU)
    palm(Vector3(30,0,-18),rng.randf_range(9,12),rng.randf()*TAU)
    placement=previous

func neighborhoods()->void:
    for x in [-240.0,-80.0,80.0,240.0]:
        for z in [-240.0,-80.0,80.0,240.0]:
            if x==-240 and absf(z)==240:continue
            var accent:="pink" if (int(x+z)/160)%2==0 else "aqua"
            if x==-240:villa(Vector3(-284,0,z+20),accent,true,-PI*.5)
            else:villa(Vector3(x-35,0,z+44),accent,true)
            villa(Vector3(x+35,0,z-44),"coral" if accent=="aqua" else "aqua",true,PI)
    # Palm-lined avenues keep the scene airy instead of filling every block.
    for z in range(-280,281,80):
        for x in [-147.5,12.5,334.0]:palm(Vector3(x,0,z),10.5,rng.randf()*TAU)
    for x in range(-280,281,80):
        for z in [-334.0,334.0]:palm(Vector3(x,0,z),11,rng.randf()*TAU)

func promenade()->void:
    box(Vector3(-343,.05,0),Vector3(14,.1,738),"white")
    box(Vector3(-352,.2,0),Vector3(.7,.4,738),"pink")
    for z in range(-275,276,55):
        palm(Vector3(-337,0,z),12+rng.randf_range(-1,1),rng.randf()*TAU)
        palm(Vector3(-303,0,z+17),11+rng.randf_range(-1,1),rng.randf()*TAU)
    for z in range(-290,291,70):
        box(Vector3(-344,.55,z),Vector3(1.5,.18,3.8),"coral")
        for dz in [-1.4,1.4]:box(Vector3(-344,.25,z+dz),Vector3(1.2,.5,.14),"white")

func parked_car(pos:Vector3,yaw:float,color:String)->void:
    var basis:=Basis(Vector3.UP,yaw)
    box(pos+basis*Vector3(0,.7,0),Vector3(1.8,.8,4.2),color,false,yaw)
    box(pos+basis*Vector3(0,1.3,.1),Vector3(1.55,.65,2.2),"navy",false,yaw)
    box(pos+basis*Vector3(0,1.68,.1),Vector3(1.62,.12,2.25),color,false,yaw)
    for x in [-.92,.92]:
        for z in [-1.3,1.3]:oval(pos+basis*Vector3(x,.43,z),Vector3(.22,.77,.77),"navy")
    for z in [-2.12,2.12]:box(pos+basis*Vector3(0,.5,z),Vector3(1.8,.17,.1),"white",false,yaw)

func yacht(pos:Vector3,length:float,yaw:float,sailing:bool=false)->void:
    var basis:=Basis(Vector3.UP,yaw)
    box(pos+basis*Vector3(0,.3,0),Vector3(length*.26,.8,length),"white",false,yaw)
    box(pos+basis*Vector3(0,.85,0),Vector3(length*.23,.18,length*.92),"navy",false,yaw)
    box(pos+basis*Vector3(0,1.45,length*.06),Vector3(length*.17,1.1,length*.45),"white",false,yaw)
    box(pos+basis*Vector3(0,2.2,length*.05),Vector3(length*.13,.6,length*.24),"navy",false,yaw)
    box(pos+basis*Vector3(0,2.6,length*.05),Vector3(length*.17,.15,length*.30),"white",false,yaw)
    if sailing:
        var mast:=pos+basis*Vector3(0,1,-length*.1)
        beam(mast,mast+Vector3(0,length*.9,0),.10,"white")
        triangle("sail",mast+Vector3(0,1,0),mast+Vector3(0,length*.85,0),mast+basis*Vector3(0,1,length*.52),basis*Vector3.RIGHT)

func marina()->void:
    box(Vector3(-399,.1,-80),Vector3(110,.3,5),"white")
    for z in [-106.0,-54.0]:box(Vector3(-445,.1,z),Vector3(5,.3,54),"white")
    yacht(Vector3(-431,-.1,-116),24,PI*.5)
    yacht(Vector3(-433,-.1,-43),20,PI*.5)
    yacht(Vector3(-560,-.1,80),26,-.3,true)
    yacht(Vector3(-700,-.1,-280),31,.5,true)
