"""Author the Pacific City map in Blender, export geometry and matching gameplay metadata."""
import bpy, math, random, json, os
from mathutils import Vector
random.seed(2718)
BASE='/Users/dadorindmitrii/Documents/blender-top'
scene=bpy.data.scenes.new('Pacific_City');bpy.context.window.scene=scene
scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
root=bpy.data.objects.new('PacificCity',None);scene.collection.objects.link(root)
materials=[]
def material(name,c,metal=0,rough=.75):
 m=bpy.data.materials.new('City_'+name);m.diffuse_color=(*c,1);m.use_nodes=True
 p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Base Color'].default_value=(*c,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough;materials.append(m);return len(materials)-1
asphalt=material('Asphalt',(.10,.11,.12),0,.9)
concrete=material('Concrete',(.30,.30,.28))
curb=material('Pale stone',(.65,.63,.56))
tile=material('Paving joints',(.23,.23,.21))
white=material('Road white',(.82,.82,.74))
yellow=material('Road yellow',(.85,.57,.10))
black=material('Street metal',(.035,.045,.05),.45,.4)
glass=material('Blue glass',(.075,.16,.21),.55,.23)
litglass=material('Warm glass',(.40,.32,.20),.35,.35)
stone=[material('Facade%d'%i,c) for i,c in enumerate([(.44,.46,.47),(.60,.56,.47),(.38,.43,.46),(.58,.59,.57),(.28,.33,.35)])]
leaf=material('Palm green',(.12,.23,.095))
trunk=material('Palm bark',(.27,.19,.12))
red=material('Terracotta',(.48,.14,.10))
blue=material('Store blue',(.07,.23,.27))
grass=material('Park grass',(.23,.30,.14))
chrome=material('Metal',(.42,.46,.47),.7,.3)
# A Blender UV-mapped road material exports as standard glTF PBR.
m=materials[asphalt];p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');im=bpy.data.images.load(BASE+'/godot-car/textures/asphalt_albedo.png',check_existing=True);tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im;m.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])
class Batch:
 def __init__(self):self.v=[];self.f=[];self.m=[]
 def face(self,points,mat):
  start=len(self.v);self.v.extend([(x,-z,y) for x,y,z in points]);self.f.append(tuple(range(start,start+len(points))));self.m.append(mat)
 def box(self,p,size,mat):
  x,y,z=p;w,h,d=[s/2 for s in size]
  v=[(x-w,y-h,z-d),(x+w,y-h,z-d),(x+w,y+h,z-d),(x-w,y+h,z-d),(x-w,y-h,z+d),(x+w,y-h,z+d),(x+w,y+h,z+d),(x-w,y+h,z+d)]
  for f in [(0,3,2,1),(4,5,6,7),(0,4,7,3),(1,2,6,5),(3,7,6,2),(0,1,5,4)]:self.face([v[i] for i in f],mat)
 def beam(self,a,b,r,mat,sides=8,r2=None):
  a,b=Vector(a),Vector(b);up=(b-a).normalized();right=up.cross(Vector((0,0,1)))
  if right.length<.1:right=up.cross(Vector((1,0,0)))
  right.normalize();other=up.cross(right);r2=r if r2 is None else r2
  lower=[a+(right*math.cos(i*math.tau/sides)+other*math.sin(i*math.tau/sides))*r for i in range(sides)]
  upper=[b+(right*math.cos(i*math.tau/sides)+other*math.sin(i*math.tau/sides))*r2 for i in range(sides)]
  for i in range(sides):j=(i+1)%sides;self.face([lower[i],lower[j],upper[j],upper[i]],mat)
  self.face(lower[::-1],mat);self.face(upper,mat)
 def save(self,name):
  me=bpy.data.meshes.new(name);me.from_pydata(self.v,[],self.f);me.update()
  for m in materials:me.materials.append(m)
  for poly,m in zip(me.polygons,self.m):poly.material_index=m
  uv=me.uv_layers.new(name='UVMap')
  for poly in me.polygons:
   for li in poly.loop_indices:
    v=me.vertices[me.loops[li].vertex_index].co
    uv.data[li].uv=(v.x*.42,v.y*.42) if poly.material_index==asphalt else (v.x*.05,v.z*.05)
  # Correct winding after axis conversion and keep crisp architecture edges.
  import bmesh
  bm=bmesh.new();bm.from_mesh(me)
  # Road paint boxes need closed topology before outward normals are computed.
  # Per-face duplicate vertices otherwise let some top faces point downward.
  if name=='StreetNetwork':bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001)
  bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
  ob=bpy.data.objects.new(name,me);scene.collection.objects.link(ob);ob.parent=root;return ob
metadata={'colliders':[],'signals':[],'streets':[-480,-320,-160,0,160,320,480],'extent':580,'building_count':0}
def collider(p,size):metadata['colliders'].append({'position':p,'size':size})
road=Batch();road.box((0,-.035,0),(1180,.18,1180),asphalt)
# All streets share the same top plane, so intersections have no overlapping asphalt.
for axis in metadata['streets']:
 for a,b in zip(metadata['streets'][:-1],metadata['streets'][1:]):
  mid=(a+b)/2;length=b-a-22
  for off in [-.15,.15]:
   road.box((axis+off,.059,mid),(.09,.008,length),yellow)
   road.box((mid,.059,axis+off),(length,.008,.09),yellow)
  for off in [-6.4,6.4]:
   road.box((axis+off,.059,mid),(.10,.008,length),white)
   road.box((mid,.059,axis+off),(length,.008,.10),white)
  # Dashed lane dividers and parking lanes.
  for along in range(a+18,b-16,9):
   for off in [-3.8,3.8]:
    road.box((axis+off,.059,along),(.075,.008,3.4),white)
    road.box((along,.059,axis+off),(3.4,.008,.075),white)
 for crossing in metadata['streets']:
  for off in [-9,9]:
   for stripe in range(-5,6,2):
    road.box((axis+stripe,.063,crossing+off),(.9,.009,2.4),white)
    road.box((axis+off,.063,crossing+stripe),(2.4,.009,.9),white)
road.save('StreetNetwork')
collider((0,-.445,0),(1180,1,1180))

def palm(batch,x,z,h=10):
 for j in range(6):
  t=j/6;u=(j+1)/6
  batch.beam((x+t*t*.65,.18+t*h,z),(x+u*u*.65,.18+u*h,z),.19*(1-t*.35),trunk,8,.19*(1-u*.35))
 crown=Vector((x+.65,h+.18,z))
 for j in range(10):
  angle=j*math.tau/10+random.random()*.15;rad=Vector((math.cos(angle),0,math.sin(angle)));side=Vector((-math.sin(angle),0,math.cos(angle)))
  for k in range(6):
   t=k/6;u=(k+1)/6
   p=crown+rad*t*3.6+Vector((0,math.sin(t*math.pi)*1.15-t*1.3,0))
   q=crown+rad*u*3.6+Vector((0,math.sin(u*math.pi)*1.15-u*1.3,0))
   width=.48*math.sin((t+.05)*math.pi)
   batch.face([p,p+side*width-rad*.28,q],leaf);batch.face([p,q,p-side*width-rad*.28],leaf)

def building(batch,x,z,w,d,h,mat):
 metadata['building_count']+=1
 batch.box((x,h/2+.18,z),(w,h,d),mat);collider((x,h/2+.18,z),(w,h,d))
 batch.box((x,1.7,z),(w+.6,3,d+.6),mat)
 # Storey lines and individually inset window panels on all four facades.
 for floor in range(1,max(2,int(h/3.8))):
  y=2.3+floor*3.8
  if y+2>h:break
  for xx in range(max(1,int((w-2)/3.6))):
   xc=x-w/2+2.1+xx*3.6
   for side in [-1,1]:
    zz=z+side*(d/2+.022)
    batch.face([(xc-1,y,zz),(xc+1,y,zz),(xc+1,y+2.1,zz),(xc-1,y+2.1,zz)],litglass if random.random()<.08 else glass)
  for zz in range(max(1,int((d-2)/3.6))):
   zc=z-d/2+2.1+zz*3.6
   for side in [-1,1]:
    xc=x+side*(w/2+.022)
    batch.face([(xc,y,zc-1),(xc,y,zc+1),(xc,y+2.1,zc+1),(xc,y+2.1,zc-1)],glass)
  if floor%3==0:batch.box((x,y-.3,z),(w+.16,.16,d+.16),mat)
 batch.box((x,h+.5,z),(w+1,.8,d+1),mat)
 batch.box((x+w*.12,h+1.7,z),(w*.32,2,d*.28),concrete)
 for dx in [-w*.22,w*.22]:batch.box((x+dx,h+1,z+d*.22),(3,1.2,3),black)
 # Retail glazing and canopy at street level.
 batch.box((x,1.6,z+d/2+.04),(w*.75,2.3,.12),glass)
 batch.box((x,3.1,z+d/2+1.0),(w*.85,.18,2.2),blue if random.random()>.5 else red)

for ix in range(6):
 for iz in range(6):
  batch=Batch();mx=-400+ix*160;mz=-400+iz*160
  batch.box((mx,.115,mz),(145.7,.12,145.7),concrete)
  # Shallow curbs and paving around every block.
  for side in [-1,1]:
   batch.box((mx+side*72.8,.18,mz),(.28,.13,145.6),curb)
   batch.box((mx,.18,mz+side*72.8),(145.6,.13,.28),curb)
  for line in range(-65,70,7):
   batch.box((mx+line,.178,mz),(.025,.006,145.3),tile)
   batch.box((mx,.178,mz+line),(145.3,.006,.025),tile)
  is_park=(ix,iz) in [(1,4),(4,1),(4,4)]
  if is_park:
   batch.box((mx,.21,mz),(116,.08,116),grass)
   batch.box((mx,.26,mz),(5,.04,130),curb);batch.box((mx,.26,mz),(130,.04,5),curb)
   for xoff in [-45,-20,20,45]:
    for zoff in [-45,45]:palm(batch,mx+xoff,mz+zoff,random.uniform(8,13))
  else:
   for dx in [-35,35]:
    for dz in [-35,35]:
     dist=math.hypot(mx+dx,mz+dz)
     h=random.uniform(50,145) if dist<300 else random.uniform(15,57)
     if ix==2 and iz==2 and dx>0 and dz>0:h=185
     building(batch,mx+dx,mz+dz,random.uniform(29,47),random.uniform(31,48),h,random.choice(stone))
  for dx in [-63,63]:
   for dz in [-55,55]:palm(batch,mx+dx,mz+dz,random.uniform(8,12))
  # Benches, planters, trash cans, hydrants and bus shelter.
  for side in [-1,1]:
   x=mx+side*64;z=mz
   batch.box((x,.55,z),(1.1,.16,3.5),trunk)
   batch.box((x+.48,1.0,z),(.14,.9,3.5),trunk)
   for zz in [-1.2,1.2]:batch.box((x,.3,z+zz),(.8,.6,.15),black)
   batch.beam((x,.18,z+6),(x,1.0,z+6),.3,black)
   batch.beam((x,.18,z-6),(x,.8,z-6),.12,red)
  batch.box((mx-56,2.6,mz+66),(9,.18,2.5),black)
  for dx in [-4,4]:batch.box((mx-56+dx,1.4,mz+67),(.10,2.6,.1),black)
  batch.box((mx-56,1.4,mz+67),(8,2.3,.04),glass)
  batch.save('Block_%d_%d'%(ix,iz))

street=Batch()
# Lamp posts and parked vehicles: curb lanes leave the driving lanes open.
for axis in metadata['streets']:
 for coord in range(-420,470,80):
  for side in [-1,1]:
   x=axis+side*8.5;z=coord
   street.beam((x,.1,z),(x,8,z),.09,black)
   street.beam((x,8,z),(x-side*2.2,8.3,z),.07,black)
   street.box((x-side*2.3,8.25,z),(.9,.12,.35),chrome)
  if random.random()<.65:
   x=axis+5.5;z=coord+10;c=random.choice([blue,chrome,red,stone[0]])
   street.box((x,.72,z),(1.8,.75,4.1),c);street.box((x,1.3,z-.2),(1.65,.7,2.0),glass)
   for xx in [-.9,.9]:
    for zz in [-1.25,1.25]:street.box((x+xx,.4,z+zz),(.20,.65,.65),black)
   collider((x,.8,z),(1.9,1.5,4.2))
# Four functioning signal heads at every junction. JSON keeps exact lens positions.
for x in metadata['streets']:
 for z in metadata['streets']:
  for direction in [(0,-1),(0,1),(1,0),(-1,0)]:
   dx,dz=direction;right=(-dz,dx)
   head=(x-dx*9+right[0]*2.5,5.5,z-dz*9+right[1]*2.5)
   pole=(x-dx*9+right[0]*8.1,.1,z-dz*9+right[1]*8.1)
   street.beam(pole,(pole[0],5.9,pole[2]),.10,black)
   street.beam((pole[0],5.9,pole[2]),(head[0],5.9,head[2]),.075,black)
   street.box(head,(.48,1.1,.26) if dx==0 else (.26,1.1,.48),black)
   metadata['signals'].append({'position':list(head),'direction':[dx,0,dz],'axis':0 if dx==0 else 1,'offset':((int(x/160)+int(z/160))%3)*2})
# Simple district gateway, billboards and plaza furniture.
for x,z in [(-74,346),(76,185),(-245,-72),(243,-245)]:
 street.beam((x,.2,z),(x,12,z),.3,black)
 street.box((x,13,z),(14,5,.35),blue)
 street.box((x,13,z+.2),(12.5,.12,.05),white)
street.save('StreetFurniture')
# Readable street names and storefront signage are real converted Blender text meshes.
for i,(name,x,z) in enumerate([('PACIFIC CITY',-74,346),('SUNSET BLVD',76,185),('DOWNTOWN',-245,-72),('GRAND AVENUE',243,-245),('PACIFIC HOTEL',-365,382),('COFFEE',55,377)]):
 curve=bpy.data.curves.new(name,'FONT');curve.body=name;curve.align_x='CENTER';curve.size=1.1 if i<4 else .75;curve.extrude=.012;curve.materials.append(materials[white])
 ob=bpy.data.objects.new(name,curve);scene.collection.objects.link(ob);ob.location=(x,-z-.24,13.4 if i<4 else 4.0);ob.rotation_euler=(math.pi/2,0,0);ob.parent=root
 bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob;bpy.ops.object.convert(target='MESH')
# Opaque facade textures avoid window/wall depth fighting at distance.
exec(compile(open(BASE+'/godot-car/tools/bake_city_windows.py').read(), 'bake_city_windows.py', 'exec'))
# Dressing is shared with the incremental update of an existing Blender city.
_enrichment={"__name__":"city_enrichment"}
exec(compile(open(BASE+'/godot-car/tools/enrich_city_blender.py').read(),'enrich_city_blender.py','exec'),_enrichment)
_enrichment['enrich_city'](scene,root,metadata)
# Export all city geometry only, before adding authoring camera and lights.
bpy.ops.object.select_all(action='DESELECT')
root.select_set(True)
for ob in root.children:ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=BASE+'/godot-car/assets/pacific_city.glb',export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,export_cameras=False,export_lights=False)
with open(BASE+'/godot-car/assets/pacific_city.json','w') as f:json.dump(metadata,f)
world=bpy.data.worlds.new('Pacific Sky');world.color=(.35,.42,.50);scene.world=world
sun=bpy.data.lights.new('California Sun','SUN');sun.energy=2;sun.angle=.15;ob=bpy.data.objects.new('California Sun',sun);scene.collection.objects.link(ob);ob.rotation_euler=(.4,-.5,-.3)
data=bpy.data.cameras.new('City overview');cam=bpy.data.objects.new('City overview',data);scene.collection.objects.link(cam);cam.location=(680,740,620);target=Vector((0,0,25));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();data.type='ORTHO';data.clip_end=5000;data.ortho_scale=1350;scene.camera=cam
scene.render.resolution_x=1400;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D':
   area.spaces.active.region_3d.view_location=target;area.spaces.active.region_3d.view_rotation=cam.rotation_euler.to_quaternion();area.spaces.active.region_3d.view_distance=1400;area.spaces.active.clip_end=5000;area.spaces.active.shading.color_type='MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=BASE+'/pacific_city.blend')
print('CITY_EXPORTED',metadata['building_count'],'buildings',len(metadata['signals']),'traffic heads',len(metadata['colliders']),'colliders')
