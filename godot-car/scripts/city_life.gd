extends Node3D
## Shared sculpted meshes, articulated limbs and planted-foot walking.
var walkers:Array[Dictionary]=[]
var time:=0.0
var meshes:Dictionary={}
var shirts:Array[StandardMaterial3D]=[]
var trousers:Array[StandardMaterial3D]=[]
var skins:Array[StandardMaterial3D]=[]
var hairs:Array[StandardMaterial3D]=[]
var shoes:StandardMaterial3D
var eye_material:StandardMaterial3D
var trim:StandardMaterial3D
var lips:Array[StandardMaterial3D]=[]

func material(color:Color,roughness:float=.85) -> StandardMaterial3D:
    var m:=StandardMaterial3D.new()
    m.albedo_color=color
    m.roughness=roughness
    return m

func ellipsoid(key:String,size:Vector3) -> Mesh:
    if not meshes.has(key):
        var sphere:=SphereMesh.new()
        sphere.radius=.5
        sphere.height=1.0
        sphere.radial_segments=16
        sphere.rings=8
        var surface:=SurfaceTool.new()
        surface.create_from(sphere,0)
        var arrays:=surface.commit_to_arrays()
        var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
        var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
        for i in vertices.size():
            vertices[i]*=size
            normals[i]=(normals[i]/size).normalized()
        arrays[Mesh.ARRAY_VERTEX]=vertices
        arrays[Mesh.ARRAY_NORMAL]=normals
        var mesh:=ArrayMesh.new()
        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
        meshes[key]=mesh
    return meshes[key]

func loft(key:String,rings:Array,sides:int=16) -> Mesh:
    if meshes.has(key):return meshes[key]
    var surface:=SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    var points:Array[PackedVector3Array]=[]
    for ring in rings:
        var row:=PackedVector3Array()
        for i in sides:
            var angle:=TAU*i/sides
            row.append(Vector3(cos(angle)*ring.y,ring.x,sin(angle)*ring.z+ring.w))
        points.append(row)
    var rising:bool=rings[-1].x>rings[0].x
    for j in range(points.size()-1):
        for i in sides:
            var k:=(i+1)%sides
            var quad:Array=[points[j][i],points[j+1][i],points[j+1][k],points[j][k]]
            for index in ([0,2,1,0,3,2] if rising else [0,1,2,0,2,3]):surface.add_vertex(quad[index])
    for end in [0,points.size()-1]:
        for i in sides:
            var k:=(i+1)%sides
            var center:=Vector3(0,rings[end].x,rings[end].w)
            var triangle:Array=[center,points[end][i],points[end][k]] if end==0 else [center,points[end][k],points[end][i]]
            for index in ([0,2,1] if rising else [0,1,2]):surface.add_vertex(triangle[index])
    surface.index()
    surface.generate_normals()
    meshes[key]=surface.commit()
    return meshes[key]

func part(parent:Node3D,name:String,mesh:Mesh,position:Vector3,mat:Material) -> MeshInstance3D:
    var ob:=MeshInstance3D.new()
    ob.name=name
    ob.mesh=mesh
    ob.position=position
    ob.material_override=mat
    ob.visibility_range_end=115
    parent.add_child(ob)
    return ob

func pivot(parent:Node3D,name:String,pos:Vector3) -> Node3D:
    var node:=Node3D.new()
    node.name=name
    node.position=pos
    parent.add_child(node)
    return node

func _ready() -> void:
    name="Pedestrians"
    for c in [Color("995339"),Color("354c60"),Color("c9c1ae"),Color("5b6845"),Color("785065"),Color("b18c45"),Color("353c42")]:shirts.append(material(c))
    for c in [Color("29394c"),Color("454642"),Color("81745b")]:trousers.append(material(c))
    for c in [Color("d6a080"),Color("a27352"),Color("68462f"),Color("e0bb9d")]:skins.append(material(c,.65))
    for c in [Color("30251d"),Color("76604a"),Color("211c1a"),Color("8a8374")]:hairs.append(material(c))
    shoes=material(Color("28272a"),.65)
    eye_material=material(Color("302b29"),.92)
    eye_material.metallic_specular=0.0
    for skin in skins:lips.append(material(skin.albedo_color*Color(.74,.57,.55,1),.85))
    trim=material(Color("a7a39a"))
    var rng:=RandomNumberGenerator.new()
    rng.seed=83217
    for ix in 6:
        for iz in 6:
            var center:=Vector3(-400+ix*160,.18,-400+iz*160)
            for side in [-1,1]:
                add_walker(center+Vector3(side*69,0,-45),center+Vector3(side*69,0,45),rng)
                add_walker(center+Vector3(-46,0,side*69),center+Vector3(46,0,side*69),rng)
    for walker in walkers:
        if absf(walker.a.x)==11.0 and walker.a.z==355.0:
            walker.offset=28.0 if walker.a.x>0 else float(walker.duration)+37.0
    update_walkers(0)

func add_walker(a:Vector3,b:Vector3,rng:RandomNumberGenerator) -> void:
    var person:=pivot(self,"Walker%03d"%walkers.size(),a)
    var height:=rng.randf_range(.93,1.07)
    person.scale=Vector3(height*rng.randf_range(.92,1.08),height,height)
    var shirt:=shirts[rng.randi_range(0,shirts.size()-1)]
    var pants:=trousers[rng.randi_range(0,trousers.size()-1)]
    var skin:=skins[rng.randi_range(0,skins.size()-1)]
    var hair:=hairs[rng.randi_range(0,hairs.size()-1)]
    var variant:=rng.randi_range(0,3)
    var body:=pivot(person,"PelvisAndSpine",Vector3(0,.89,0))
    part(body,"Hips",ellipsoid("hips",Vector3(.32,.24,.23)),Vector3.ZERO,pants)
    var torso:=loft("jacket" if variant==0 else "shirt",[
        Vector4(.04,.155,.105,0),Vector4(.13,.16,.105,0),Vector4(.31,.195,.12,-.006),
        Vector4(.43,.205,.115,0),Vector4(.49,.14,.09,0),Vector4(.51,.075,.075,0)])
    part(body,"ClothedTorso",torso,Vector3.ZERO,shirt)
    part(body,"Neck",ellipsoid("neck",Vector3(.10,.14,.10)),Vector3(0,.54,0),skin)
    var head:=pivot(body,"Head",Vector3(0,.72,-.008))
    var face_mesh:=loft("face_sculpt",[
        Vector4(-.145,.042,.055,-.01),Vector4(-.11,.08,.078,-.012),Vector4(-.055,.10,.095,-.004),
        Vector4(.01,.115,.105,.005),Vector4(.065,.111,.101,.008),Vector4(.12,.086,.079,.012),Vector4(.153,.025,.03,.012)],24)
    part(head,"Face",face_mesh,Vector3.ZERO,skin)
    part(head,"Nose",ellipsoid("nose",Vector3(.030,.056,.032)),Vector3(0,-.006,-.101),skin)
    part(head,"NoseTip",ellipsoid("nose_tip",Vector3(.035,.024,.032)),Vector3(0,-.028,-.116),skin)
    for side in [-1,1]:
        part(head,"Ear",ellipsoid("ear",Vector3(.033,.063,.037)),Vector3(side*.12,-.012,0),skin)
        part(head,"Eye",ellipsoid("eye",Vector3(.020,.008,.009)),Vector3(side*.044,.023,-.098),eye_material)
    part(head,"Mouth",ellipsoid("mouth",Vector3(.043,.006,.007)),Vector3(0,-.065,-.095),lips[skins.find(skin)])
    # A shaped hair cap exposes the face and jaw rather than covering the head.
    var hair_mesh:=loft("hair_cap",[Vector4(.048,.120,.114,.012),Vector4(.10,.108,.100,.012),Vector4(.147,.069,.067,.012),Vector4(.17,.012,.012,.012)])
    part(head,"Hair",hair_mesh,Vector3.ZERO,hair)
    if variant==1:
        part(head,"LongHair",ellipsoid("long_hair",Vector3(.21,.32,.09)),Vector3(0,-.055,.105),hair)
    var legs:Array[Dictionary]=[]
    var arms:Array[Dictionary]=[]
    for side in [-1,1]:
        var thigh:=pivot(person,"Hip",Vector3(side*.09,.89,0))
        part(thigh,"TrouserThigh",loft("thigh",[Vector4(0,.092,.095,0),Vector4(-.19,.085,.09,0),Vector4(-.44,.060,.067,0)]),Vector3.ZERO,pants)
        var knee:=pivot(thigh,"Knee",Vector3(0,-.44,0))
        part(knee,"TrouserShin",loft("shin",[Vector4(0,.062,.067,0),Vector4(-.20,.066,.068,.008),Vector4(-.44,.044,.049,0)]),Vector3.ZERO,pants)
        var foot:=pivot(knee,"Ankle",Vector3(0,-.44,0))
        part(foot,"Shoe",ellipsoid("shoe",Vector3(.13,.105,.27)),Vector3(0,-.033,-.047),shoes)
        legs.append({"hip":thigh,"knee":knee,"foot":foot})
        var shoulder:=pivot(body,"Shoulder",Vector3(side*.205,.43,0))
        part(shoulder,"Sleeve",loft("upper_arm",[Vector4(.02,.077,.080,0),Vector4(-.13,.064,.065,0),Vector4(-.28,.054,.058,0)]),Vector3.ZERO,shirt)
        var elbow:=pivot(shoulder,"Elbow",Vector3(0,-.28,0))
        part(elbow,"Forearm",loft("forearm",[Vector4(0,.052,.056,0),Vector4(-.12,.046,.05,0),Vector4(-.25,.030,.034,0)]),Vector3.ZERO,shirt if variant==0 else skin)
        part(elbow,"Hand",ellipsoid("hand",Vector3(.065,.12,.035)),Vector3(0,-.30,-.007),skin)
        arms.append({"shoulder":shoulder,"elbow":elbow})
    # A narrow seam, collar and occasional bag distinguish outfits at street distance.
    part(body,"Collar",ellipsoid("collar",Vector3(.13,.045,.135)),Vector3(0,.475,0),trim)
    if variant==0:
        part(body,"JacketFastener",ellipsoid("zip",Vector3(.008,.35,.007)),Vector3(0,.26,-.119),trim)
    if variant==2:
        part(body,"Backpack",ellipsoid("backpack",Vector3(.27,.37,.16)),Vector3(0,.25,.17),pants)
    var speed:=rng.randf_range(.95,1.45)
    var duration:=a.distance_to(b)/speed+.6
    walkers.append({"node":person,"body":body,"head":head,"a":a,"b":b,"speed":speed,"length":a.distance_to(b),"duration":duration,"offset":rng.randf()*(duration*2+4),"arms":arms,"legs":legs,"phase":rng.randf()})

func distance_at(t:float,duration:float,speed:float,length:float)->float:
    if t<.6:return speed*t*t/1.2
    if t>duration-.6:return length-speed*(duration-t)*(duration-t)/1.2
    return speed*(t-.3)

func animate_walker(walker:Dictionary,distance:float,weight:float) -> void:
    var phase:=fposmod(distance/float(walker.node.scale.z)+float(walker.phase),1.0)
    var sway:=sin(phase*TAU)
    var bob:=cos(phase*TAU*2)*.011*weight
    walker.body.position.y=.89+bob
    walker.body.rotation.y=sway*.035*weight
    walker.body.rotation.z=sway*.012*weight
    walker.head.rotation.y=sin(time*.55+float(walker.phase)*6)*.08
    for i in 2:
        var cycle:=fposmod(phase+i*.5,1)
        var foot_z:float
        var lift:=0.0
        if cycle<.6:
            foot_z=lerpf(-.3,.3,cycle/.6)
        else:
            var swing:float=(cycle-.6)/.4
            foot_z=lerpf(.3,-.3,smoothstep(0,1,swing))
            lift=sin(swing*PI)*.115
        foot_z*=weight
        lift*=weight
        var dy:=.085+lift-(.89+bob)
        var d:=clampf(Vector2(dy,foot_z).length(),.1,.879)
        var aim:=atan2(-foot_z,-dy)
        var bend:=acos(clampf(d/(.44*2),-1,1))
        var hip_angle:=aim+bend
        var knee_angle:=-2*bend
        walker.legs[i].hip.position.y=.89+bob
        walker.legs[i].hip.rotation.x=hip_angle
        walker.legs[i].knee.rotation.x=knee_angle
        walker.legs[i].foot.rotation.x=-hip_angle-knee_angle
        walker.arms[i].shoulder.rotation.x=(-sway if i==0 else sway)*.32*weight
        walker.arms[i].shoulder.rotation.z=(-.06 if i==0 else .06)
        walker.arms[i].elbow.rotation.x=.10+(.10+absf(sway)*.12)*weight

func update_walkers(delta:float) -> void:
    time+=delta
    var camera:=get_viewport().get_camera_3d()
    for walker in walkers:
        var duration:float=walker.duration
        var t:=fposmod(time+float(walker.offset),duration*2+4)
        var outbound:=t<duration+2
        var local:float=t if outbound else t-duration-2
        var distance:=distance_at(minf(local,duration),duration,walker.speed,walker.length)
        var travel:float=distance/float(walker.length)
        var location:Vector3=walker.a.lerp(walker.b,travel if outbound else 1-travel)
        var person:Node3D=walker.node
        person.position=location
        person.visible=camera==null or camera.global_position.distance_squared_to(location)<13225
        if not person.visible:continue
        var direction:Vector3=(walker.b-walker.a).normalized()*(1 if outbound else -1)
        if local>duration+.5:direction=-direction
        var yaw:=atan2(-direction.x,-direction.z)
        person.rotation.y=lerp_angle(person.rotation.y,yaw,minf(1,delta*5)) if delta>0 else yaw
        var weight:=smoothstep(0,.45,local)*(1-smoothstep(duration-.45,duration,local))
        animate_walker(walker,distance+(0 if outbound else float(walker.length)),weight)

func _process(delta:float) -> void:
    update_walkers(delta)
