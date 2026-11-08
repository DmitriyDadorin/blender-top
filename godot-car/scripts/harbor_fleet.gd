@tool
extends Node3D
## Anchored vessels share a few batched surfaces each. Cabin panes replace wall
## sections, so there are no coplanar lit quads to shimmer at long distance.
var boats:Array[Dictionary]=[]
var night_mode:=false
var materials:Dictionary={}
var surfaces:Dictionary={}
var navigation:Array[StandardMaterial3D]=[]
var cabin_material:StandardMaterial3D

func material(key:String,color:Color,metal:float=0,roughness:float=.6)->void:
    var m:=StandardMaterial3D.new()
    m.albedo_color=color
    m.metallic=metal
    m.roughness=roughness
    materials[key]=m

func surface(key:String)->SurfaceTool:
    if not surfaces.has(key):
        var s:=SurfaceTool.new()
        s.begin(Mesh.PRIMITIVE_TRIANGLES)
        surfaces[key]=s
    return surfaces[key]

func primitive(key:String,mesh:Mesh,pos:Vector3,size:Vector3,rotation:Basis=Basis.IDENTITY)->void:
    surface(key).append_from(mesh,0,Transform3D(rotation.scaled(size),pos))

func box(key:String,pos:Vector3,size:Vector3)->void:
    primitive(key,BoxMesh.new(),pos,size)

func beam(key:String,a:Vector3,b:Vector3,radius:float)->void:
    var mesh:=CylinderMesh.new()
    mesh.top_radius=radius*.8
    mesh.bottom_radius=radius
    mesh.height=a.distance_to(b)
    mesh.radial_segments=8
    var y:Vector3=(b-a).normalized()
    var x:Vector3=y.cross(Vector3.FORWARD).normalized()
    if x.length()<.01:x=Vector3.RIGHT
    var z:=x.cross(y).normalized()
    surface(key).append_from(mesh,0,Transform3D(Basis(x,y,z),(a+b)*.5))

func face(key:String,points:Array,outward:Vector3)->void:
    var s:=surface(key)
    for i in range(1,points.size()-1):
        var a:Vector3=points[0]
        var b:Vector3=points[i]
        var c:Vector3=points[i+1]
        var n:Vector3=(c-a).cross(b-a).normalized()
        if n.dot(outward)<0:
            var swap:=b;b=c;c=swap;n=-n
        for p in [a,b,c]:
            s.set_normal(n)
            s.add_vertex(p)

func hull(length:float,width:float,height:float,draft:float,color:String)->void:
    var rings:Array=[]
    for section in [Vector2(-.5,.025),Vector2(-.34,.48),Vector2(.34,.50),Vector2(.5,.41)]:
        var z:float=length*section.x
        var w:float=width*section.y
        rings.append([Vector3(-w*.62,-draft,z),Vector3(-w*.94,.05,z),Vector3(-w,height,z),Vector3(w,height,z),Vector3(w*.94,.05,z),Vector3(w*.62,-draft,z)])
    for j in range(rings.size()-1):
        for i in [0,1,3,4,5]:
            var k:int=(i+1)%6
            var p:Array=[rings[j][i],rings[j+1][i],rings[j+1][k],rings[j][k]]
            var center:Vector3=(p[0]+p[1]+p[2]+p[3])*.25
            face(color,p,Vector3(center.x,center.y-height*.35,0))
        face("deck",[rings[j][2],rings[j+1][2],rings[j+1][3],rings[j][3]],Vector3.UP)
    face(color,rings[0],Vector3.FORWARD)
    face(color,rings[-1],Vector3.BACK)
    # Wide bulwarks read as rails at coastal viewing distances.
    for side in [-1,1]:
        beam("white",Vector3(side*width*.43,height+.23,-length*.30),Vector3(side*width*.46,height+.23,length*.40),.09 if length<40 else .16)

func deckhouse(pos:Vector3,width:float,length:float,height:float,panes:int)->void:
    box("white",pos+Vector3(0,height*.18,0),Vector3(width,height*.36,length))
    box("white",pos+Vector3(0,height,0),Vector3(width*1.06,.18,length*1.08))
    var bottom:=height*.36
    var pane_height:=height-bottom-.10
    for side in [-1,1]:
        for i in panes:
            var step:=length/panes
            var z:float=pos.z-length*.5+step*(i+.5)
            var x:float=pos.x+side*width*.5
            var half_pane:float=(step-.17)*.5
            face("cabin",[Vector3(x,pos.y+bottom,z-half_pane),Vector3(x,pos.y+bottom+pane_height,z-half_pane),Vector3(x,pos.y+bottom+pane_height,z+half_pane),Vector3(x,pos.y+bottom,z+half_pane)],Vector3(side,0,0))
            box("white",Vector3(pos.x+side*width*.5,pos.y+bottom+pane_height*.5,z+step*.5),Vector3(.14,pane_height,.12))
    face("glass",[pos+Vector3(-width*.5+.06,bottom,-length*.5),pos+Vector3(width*.5-.06,bottom,-length*.5),pos+Vector3(width*.5-.06,bottom+pane_height,-length*.5),pos+Vector3(-width*.5+.06,bottom+pane_height,-length*.5)],Vector3.FORWARD)
    box("white",pos+Vector3(0,bottom+pane_height*.5,length*.5),Vector3(width,pane_height,.12))

func nav_light(key:String,p:Vector3,radius:float)->void:
    var sphere:=SphereMesh.new()
    sphere.radius=radius
    sphere.height=radius*2
    sphere.radial_segments=8
    sphere.rings=3
    surface(key).append_from(sphere,0,Transform3D(Basis.IDENTITY,p))

func finish_boat(label:String,position:Vector3,yaw:float,kind:String,length:float)->void:
    var mesh:=ArrayMesh.new()
    for key in surfaces:
        var builder:SurfaceTool=surfaces[key]
        builder.set_material(materials[key])
        builder.commit(mesh)
    var boat:=MeshInstance3D.new()
    boat.name=label
    boat.mesh=mesh
    boat.position=position
    boat.rotation.y=yaw
    boat.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    boat.visibility_range_end=3500
    add_child(boat)
    boats.append({"node":boat,"kind":kind,"length":length,"position":position})
    surfaces.clear()

func yacht(index:int,pos:Vector3,yaw:float,length:float)->void:
    var w:=length*.235
    hull(length,w,1.15,1.0,"white")
    deckhouse(Vector3(0,1.16,length*.04),w*.66,length*.43,2.1,5)
    box("deck",Vector3(0,3.5,length*.14),Vector3(w*.48,.15,length*.25))
    box("white",Vector3(0,3.68,length*.29),Vector3(w*.48,.3,.35))
    beam("metal",Vector3(0,3.6,length*.14),Vector3(0,6.0,length*.14),.075)
    beam("metal",Vector3(-w*.23,4.3,length*.14),Vector3(w*.23,4.3,length*.14),.055)
    nav_light("anchor",Vector3(0,6.1,length*.14),.23)
    nav_light("port",Vector3(-w*.49,2.0,-length*.17),.25)
    nav_light("starboard",Vector3(w*.49,2.0,-length*.17),.25)
    for side in [-1,1]:
        box("accent",Vector3(side*w*.48,1.43,length*.12),Vector3(.11,.07,length*.5))
    finish_boat("Yacht%02d"%index,pos,yaw,"yacht",length)

func cargo(index:int,pos:Vector3,yaw:float,length:float)->void:
    var w:=length*.145
    hull(length,w,4.0,3.2,"hull")
    for deck in 3:
        for row in 4:
            for column in 3:
                var key:="container%d"%((deck+row+column+index)%4)
                box(key,Vector3((column-1)*w*.27,5.25+deck*2.55,(-.25+row*.14)*length),Vector3(w*.25,2.45,length*.13))
    deckhouse(Vector3(0,4.1,length*.34),w*.76,length*.13,6.0,4)
    deckhouse(Vector3(0,10.3,length*.34),w*.64,length*.11,3.0,4)
    box("hull",Vector3(0,15.5,length*.38),Vector3(w*.25,4,length*.035))
    beam("metal",Vector3(0,13.5,length*.32),Vector3(0,21,length*.32),.19)
    nav_light("anchor",Vector3(0,21.2,length*.32),.55)
    nav_light("port",Vector3(-w*.5,5,-length*.30),.45)
    nav_light("starboard",Vector3(w*.5,5,-length*.30),.45)
    finish_boat("Cargo%02d"%index,pos,yaw,"cargo",length)

func liner(index:int,pos:Vector3,yaw:float,length:float)->void:
    var w:=length*.165
    hull(length,w,3.0,2.5,"hull")
    for deck in 4:
        deckhouse(Vector3(0,3.1+deck*2.5,deck*length*.025),w*(.85-deck*.08),length*(.72-deck*.08),2.3,18-deck*3)
    for z in [-length*.03,length*.12]:
        box("container1",Vector3(0,15,z),Vector3(w*.22,4,length*.08))
        box("metal",Vector3(0,17.05,z),Vector3(w*.24,.25,length*.085))
    beam("metal",Vector3(0,13,-length*.18),Vector3(0,21,-length*.18),.13)
    nav_light("anchor",Vector3(0,21.2,-length*.18),.55)
    nav_light("port",Vector3(-w*.48,5,-length*.28),.45)
    nav_light("starboard",Vector3(w*.48,5,-length*.28),.45)
    finish_boat("Liner%02d"%index,pos,yaw,"liner",length)

func build()->void:
    name="HarborFleet"
    material("white",Color(.80,.83,.83),.12,.3)
    material("hull",Color(.055,.09,.13),.3,.5)
    material("deck",Color(.33,.24,.14),0,.7)
    material("metal",Color(.23,.27,.29),.65,.38)
    material("glass",Color(.025,.07,.10),.35,.18)
    for i in 4:material("container%d"%i,[Color(.36,.10,.055),Color(.14,.23,.25),Color(.45,.37,.13),Color(.18,.26,.14)][i],.15,.65)
    material("cabin",Color(.04,.075,.09),.1,.3)
    cabin_material=materials.cabin
    for key in ["port","starboard","anchor","accent"]:
        material(key,{"port":Color(1,.015,.005),"starboard":Color(.015,.85,.12),"anchor":Color(1,.92,.73),"accent":Color(1,.66,.30)}[key])
        navigation.append(materials[key])
    var positions:Array[Vector3]=[Vector3(-630,-.45,-430),Vector3(-710,-.45,-270),Vector3(-660,-.45,-80),Vector3(-780,-.45,90),Vector3(-680,-.45,245),Vector3(-760,-.45,390),Vector3(-920,-.45,-530),Vector3(-940,-.45,520)]
    for i in positions.size():yacht(i,positions[i],[-.4,.5,1.0,-.8,.25,1.2,-.2,.7][i],20+i*1.7)
    cargo(0,Vector3(-1120,-.45,-360),.35,120)
    cargo(1,Vector3(-1470,-.45,270),-.22,155)
    cargo(2,Vector3(-1820,-.45,-750),.55,175)
    liner(0,Vector3(-1040,-.45,620),-.5,86)
    liner(1,Vector3(-1420,-.45,-60),.2,122)
    liner(2,Vector3(-2070,-.45,870),-.4,150)
    set_night(false)

func set_night(enabled:bool)->void:
    night_mode=enabled
    cabin_material.emission_enabled=enabled
    cabin_material.emission=Color(1,.58,.24)
    cabin_material.emission_energy_multiplier=1.6 if enabled else 0.0
    cabin_material.albedo_color=Color(.75,.45,.20) if enabled else Color(.04,.075,.09)
    for mat in navigation:
        mat.emission_enabled=enabled
        mat.emission=mat.albedo_color
        mat.emission_energy_multiplier=2.0 if enabled else 0.0
        mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED if enabled else BaseMaterial3D.SHADING_MODE_PER_PIXEL
    var lights:=PackedVector4Array()
    for boat in boats:
        var p:Vector3=boat.position
        lights.append(Vector4(p.x,p.z,float(boat.length)*.10,1.0 if boat.kind=="yacht" else 1.6))
    var ocean:=get_parent().get_node("Ocean") as MeshInstance3D
    ocean.material_override.set_shader_parameter("harbor_lights",lights)
    ocean.material_override.set_shader_parameter("harbor_light_count",boats.size())
    ocean.material_override.set_shader_parameter("harbor_night",1.0 if enabled else 0.0)
