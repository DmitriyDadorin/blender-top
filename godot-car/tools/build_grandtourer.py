"""Run in Blender. Creates a separate detailed car without replacing the classic asset."""
import bpy, math, os
from mathutils import Vector, Matrix
BASE='/Users/dadorindmitrii/Documents/blender-top'
# Archive names in memory only; the classic source files and GLB remain unchanged.
for name in ['CarModel','Body','Steering_FL','Steering_FR','Wheel_FL','Wheel_FR','Wheel_RL','Wheel_RR']:
    old=bpy.data.objects.get(name)
    if old: old.name='Classic_'+name
scene=bpy.data.scenes.new('GrandTourer_Studio')
bpy.context.window.scene=scene
scene.unit_settings.system='METRIC'
root=bpy.data.objects.new('CarModel',None);scene.collection.objects.link(root)
body_parts=[]; wheel_parts={}
def mat(name,c,metal=0,rough=.4):
    m=bpy.data.materials.new('GT_'+name);m.diffuse_color=(*c,1);m.use_nodes=True
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value=(*c,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    return m
paint=mat('Petrol metallic',(.035,.19,.22),.72,.24)
black=mat('Rubber trim',(.012,.016,.019),.05,.62)
tire=mat('Tires',(.018,.021,.024),0,.86)
glass=mat('Tinted glass',(.022,.045,.057),.48,.12)
chrome=mat('Brushed alloy',(.55,.60,.63),.86,.25)
darkmetal=mat('Graphite metal',(.07,.085,.10),.8,.32)
light=mat('Headlight',(.85,.94,1),.3,.17)
red=mat('Tail lens',(.48,.009,.012),.35,.2)
orange=mat('Brake caliper',(.72,.12,.025),.32,.34)
def register(o,name,m,group=None):
    o.name=name;o.data.materials.append(m)
    (body_parts if group is None else wheel_parts.setdefault(group,[])).append(o)
    return o
def bevel(o,width=.025,segments=3):
    b=o.modifiers.new('Rounded edges','BEVEL');b.width=width;b.segments=segments
    o.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
    return o
def box(name,loc,size,m,b=.02,group=None):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    register(o,name,m,group)
    if b:bevel(o,b)
    return o
def mesh(name,v,f,m):
    me=bpy.data.meshes.new(name);me.from_pydata(v,[],f);me.update();o=bpy.data.objects.new(name,me);scene.collection.objects.link(o);return register(o,name,m)
def beam(name,a,b,r,m,group=None):
    a,b=Vector(a),Vector(b);bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=r,depth=(b-a).length,location=(a+b)/2)
    o=bpy.context.object;o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return register(o,name,m,group)
def cylinder(name,loc,r,depth,m,group=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=48,radius=r,depth=depth,location=loc,rotation=(0,math.pi/2,0));o=register(bpy.context.object,name,m,group)
    bevel(o,.008,2);return o
def line(name,points,r,m):
    for a,b in zip(points[:-1],points[1:]):beam(name,a,b,r,m)
# Sculpted solid body with genuine wheel wells.
sections=[(-2.28,.77,.53,.97),(-2.07,.92,.46,1.08),(-1.45,.97,.45,1.13),(-.7,.965,.43,1.12),(.55,.95,.43,1.08),(1.43,.965,.44,1.015),(2.05,.91,.5,.96),(2.29,.79,.59,.89)]
v=[]
for y,w,low,top in sections:
    v.extend([(-w*.82,y,low),(-w,y,low+.10),(-w,y,top-.09),(-w*.87,y,top),(w*.87,y,top),(w,y,top-.09),(w,y,low+.10),(w*.82,y,low)])
f=[]
for i in range(len(sections)-1):
    for j in range(8): f.append((i*8+j,i*8+(j+1)%8,(i+1)*8+(j+1)%8,(i+1)*8+j))
f.extend([tuple(range(7,-1,-1)),tuple((len(sections)-1)*8+j for j in range(8))])
body=mesh('Sculpted body',v,f,paint)
# Recalculate normals before boolean wheel arches.
import bmesh
bm=bmesh.new();bm.from_mesh(body.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(body.data);bm.free()
for y in [-1.42,1.42]:
    bpy.ops.mesh.primitive_cylinder_add(vertices=64,radius=.485,depth=3,location=(0,y,.445),rotation=(0,math.pi/2,0))
    cutter=bpy.context.object;mod=body.modifiers.new('Wheel well','BOOLEAN');mod.object=cutter
    bpy.context.view_layer.objects.active=body;bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter,do_unlink=True)
bevel(body,.035,3)
box('Undertray',(0,-.05,.43),(1.68,3.95,.12),black,.06)
# Glass cabin, gently sloping roof, black frames and painted pillars.
front=[(-.78,.85,1.07),(.78,.85,1.07),(.69,.22,1.64),(-.69,.22,1.64)]
rear=[(-.8,-1.24,1.12),(-.70,-.72,1.66),(.70,-.72,1.66),(.8,-1.24,1.12)]
mesh('Windshield',front,[(0,1,2,3)],glass)
mesh('Rear glass',rear,[(0,1,2,3)],glass)
box('Roof',(0,-.25,1.665),(1.45,1.04,.095),paint,.09)
for side in [-1,1]:
    pts=[(side*.84,-1.17,1.12),(side*.72,-.69,1.64),(side*.71,.19,1.62),(side*.82,.8,1.08)]
    mesh('Side glass',pts,[(0,1,2,3)],glass)
    for a,b in [(front[0 if side<0 else 1],front[3 if side<0 else 2]),(rear[0 if side<0 else 3],rear[1 if side<0 else 2])]:
        beam('Pillar',a,b,.036,paint)
    line('Window seal',pts+[pts[0]],.014,black)
    beam('B pillar',(side*.79,-.46,1.11),(side*.727,-.46,1.64),.023,black)
    line('Door seam',[(side*.962,.65,1.005),(side*.968,.60,.69),(side*.971,-.78,.65),(side*.974,-.98,1.04)],.006,black)
    box('Door handle',(side*.976,-.48,1.035),(.026,.19,.037),chrome,.015)
    beam('Mirror arm',(side*.86,.52,1.12),(side*1.02,.54,1.16),.024,black)
    box('Mirror housing',(side*1.055,.56,1.18),(.22,.26,.12),paint,.055)
    box('Mirror glass',(side*1.057,.445,1.185),(.16,.012,.075),chrome,.025)
    # Raised fender lip follows the open wheel arch.
    for y in [-1.42,1.42]:
        pts=[(side*.974,y+.488*math.cos(t*math.pi/24),.445+.488*math.sin(t*math.pi/24)) for t in range(25)]
        line('Fender edge',pts,.013,paint)
    box('Rocker trim',(side*.935,-.04,.5),(.075,1.95,.07),darkmetal,.025)
# Hood panel lines and trunk.
for side in [-1,1]:
    line('Hood seam',[(side*.66,.84,1.075),(side*.61,1.42,1.014),(side*.56,2.05,.965)],.005,black)
    beam('Hood crease',(side*.42,.91,1.083),(side*.35,1.91,.985),.008,paint)
line('Trunk seam',[(-.72,-1.35,1.14),(-.68,-1.97,1.093),(.68,-1.97,1.093),(.72,-1.35,1.14)],.005,black)
box('Front grille',(0,2.267,.70),(1.26,.08,.25),black,.06)
for z in [.625,.67,.715,.76]:box('Grille fin',(0,2.313,z),(1.12,.013,.014),darkmetal,.004)
box('Front splitter',(0,2.24,.52),(1.76,.18,.065),darkmetal,.035)
box('Rear diffuser',(0,-2.245,.55),(1.72,.15,.14),black,.025)
for side in [-1,1]:
    box('Headlight housing',(side*.61,2.213,.88),(.43,.11,.17),darkmetal,.05)
    for xoff in [-.1,.1]:
        box('Projector lens',(side*.61+xoff,2.275,.885),(.115,.018,.095),light,.035)
    box('Daylight strip',(side*.61,2.285,.823),(.37,.018,.02),light,.008)
    box('Tail light',(side*.58,-2.258,.94),(.47,.055,.105),red,.035)
    box('Tail light inset',(side*.58,-2.291,.94),(.37,.01,.02),light,.005)
    o=beam('Exhaust',(side*.61,-2.12,.48),(side*.61,-2.37,.48),.063,chrome)
    beam('Exhaust opening',(side*.61,-2.366,.48),(side*.61,-2.378,.48),.049,black)
box('Rear plate',(0,-2.29,.75),(.43,.025,.15),light,.012)
box('Front plate',(0,2.325,.69),(.34,.02,.11),chrome,.012)
# Four fully separate wheels, tire tread, brake rotors, ten spokes and hub bolts.
for y,label0 in [(1.42,'F'),(-1.42,'R')]:
    for side,label1 in [(-1,'L'),(1,'R')]:
        label=label0+label1;center=Vector((side*.94,y,.445))
        bpy.ops.mesh.primitive_torus_add(major_segments=64,minor_segments=16,location=center,major_radius=.337,minor_radius=.106,rotation=(0,math.pi/2,0))
        o=register(bpy.context.object,'Tire',tire,label)
        for poly in o.data.polygons:poly.use_smooth=True
        cylinder('Rim barrel',center,.31,.18,darkmetal,label)
        outer=side*1.043
        cylinder('Brake disc',(outer-side*.027,y,.445),.262,.018,chrome,label)
        cylinder('Rim face',(outer,y,.445),.285,.012,darkmetal,label)
        for t in range(10):
            a=t*math.tau/10
            beam('Alloy spoke',(outer+side*.015,y+.09*math.sin(a),.445+.09*math.cos(a)),(outer+side*.015,y+.283*math.sin(a+.10),.445+.283*math.cos(a+.10)),.021,chrome,label)
        cylinder('Hub',(outer+side*.032,y,.445),.087,.025,chrome,label)
        for t in range(5):
            a=t*math.tau/5
            cylinder('Lug bolt',(outer+side*.05,y+.055*math.sin(a),.445+.055*math.cos(a)),.012,.012,black,label)
        box('Brake caliper',(outer-side*.035,y-.215,.49),(.045,.085,.2),orange,.025,label)
        # Black sidewall rings and fine grooves, not a flat cylinder.
        for radius in [.305,.39]:
            bpy.ops.mesh.primitive_torus_add(major_segments=64,minor_segments=6,major_radius=radius,minor_radius=.006,location=(outer,y,.445),rotation=(0,math.pi/2,0))
            register(bpy.context.object,'Sidewall ring',black,label)
        for t in range(48):
            a=t*math.tau/48
            ob=box('Tread groove',(side*.94,y+.443*math.sin(a),.445+.443*math.cos(a)),(.14,.014,.006),black,0,label);ob.rotation_euler.x=-a
# Bake geometry and join by animation part. Keep origins on axle centers.
def merge(parts,name,pivot):
    deps=bpy.context.evaluated_depsgraph_get();copies=[]
    for src in parts:
        me=bpy.data.meshes.new_from_object(src.evaluated_get(deps),depsgraph=deps);me.transform(src.matrix_world)
        ob=bpy.data.objects.new('baked',me);scene.collection.objects.link(ob);copies.append(ob)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in copies:ob.select_set(True)
    bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();ob=copies[0];ob.name=name
    ob.data.transform(Matrix.Translation(-Vector(pivot)));ob.location=pivot
    for src in parts:bpy.data.objects.remove(src,do_unlink=True)
    return ob
body=merge(body_parts,'Body',(0,0,0));body.parent=root
for label,parts in wheel_parts.items():
    pivot=Vector((-.94 if label[1]=='L' else .94,1.42 if label[0]=='F' else -1.42,.445))
    ob=merge(parts,'Wheel_'+label,pivot)
    if label[0]=='F':
        steering=bpy.data.objects.new('Steering_'+label,None);scene.collection.objects.link(steering);steering.parent=root;steering.location=pivot
        ob.parent=steering;ob.location=(0,0,0)
    else:ob.parent=root
# Export only the car, before adding the studio set.
bpy.ops.object.select_all(action='DESELECT')
for ob in scene.objects:ob.select_set(True)
try:
    bpy.ops.export_scene.gltf(filepath=BASE+'/godot-car/assets/grand_tourer.glb',export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,export_cameras=False,export_lights=False,export_animations=False)
except TypeError as e:raise RuntimeError(str(e))
# Studio is for Blender review, excluded from the exported car.
floor=box('Studio floor',(0,0,-.08),(200,200,.1),mat('Studio',(.12,.14,.16),0,.8),0)
for name,loc,power,size in [('Key',(4,4,7),1800,5),('Rim',(-4,-3,5),1600,4),('Fill',(1,-5,3),700,3)]:
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size
    ob=bpy.data.objects.new(name,data);scene.collection.objects.link(ob);ob.location=loc;ob.rotation_euler=(Vector((0,0,.8))-ob.location).to_track_quat('-Z','Y').to_euler()
data=bpy.data.cameras.new('GT Camera');cam=bpy.data.objects.new('GT Camera',data);scene.collection.objects.link(cam);cam.location=(6,7,4.4);cam.rotation_euler=(Vector((0,0,.8))-cam.location).to_track_quat('-Z','Y').to_euler();data.type='ORTHO';data.ortho_scale=6.5;scene.camera=cam
scene.world=bpy.data.worlds.new('GT Studio World');scene.world.color=(.25,.25,.25)
scene.render.resolution_x=1200;scene.render.resolution_y=850;scene.render.resolution_percentage=100
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_location=(0,0,.85);area.spaces.active.region_3d.view_rotation=cam.rotation_euler.to_quaternion();area.spaces.active.region_3d.view_distance=7.5;area.spaces.active.shading.color_type='MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=BASE+'/grand_tourer.blend')
print('GRAND_TOURER_EXPORTED',[(ob.name,len(ob.data.polygons)) for ob in root.children if ob.type=='MESH'])
