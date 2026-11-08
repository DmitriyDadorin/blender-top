"""Blender source for cactus/shrub meshes and seamless surface textures."""
import bpy, math, random, numpy as np
from mathutils import Vector
BASE='/Users/dadorindmitrii/Documents/blender-top'
random.seed(375)
scene=bpy.data.scenes.new('Desert_Asset_Workshop');bpy.context.window.scene=scene
rng=np.random.default_rng(375)
N=1024
raw=rng.random((N,N))
f=np.fft.fftfreq(N);fx,fy=np.meshgrid(f,f)
def noise(scale):
    a=np.fft.ifft2(np.fft.fft2(raw)*np.exp(-(fx*fx+fy*fy)*scale*scale)).real
    return (a-a.mean())/(a.std()+1e-6)
coarse=noise(100);medium=noise(12);fine=raw-.5
# Entirely procedural, seamless albedo and height maps; no downloaded assets.
def save_image(name,data):
    if data.ndim==2:data=np.repeat(data[:,:,None],3,axis=2)
    pixels=np.concatenate((np.clip(data,0,1),np.ones((N,N,1))),axis=2).astype(np.float32)
    image=bpy.data.images.new(name,width=N,height=N);image.colorspace_settings.name='Non-Color';image.pixels.foreach_set(pixels.ravel());image.filepath_raw=BASE+'/godot-car/textures/'+name+'.png';image.file_format='PNG';image.save();bpy.data.images.remove(image)
sand=np.array([.57,.49,.365])+coarse[:,:,None]*.018+medium[:,:,None]*.022+fine[:,:,None]*.105
save_image('sand_albedo',sand)
save_image('surface_height',.5+medium*.055+fine*.4)
asphalt=np.array([.145,.15,.152])+medium[:,:,None]*.017+fine[:,:,None]*.12
# Jagged tar-sealed fractures, branching periodically in each tile.
y,x=np.mgrid[0:N,0:N]
crack=np.abs(np.sin((x+28*np.sin(y*.018)+13*np.sin(y*.047))/N*math.pi*4))<.018
asphalt[crack]*=.42
save_image('asphalt_albedo',asphalt)
rock=np.array([.40,.345,.285])+coarse[:,:,None]*.045+medium[:,:,None]*.028+fine[:,:,None]*.08
save_image('rock_albedo',rock)

def mat(name,c,rough=.8):
    m=bpy.data.materials.new(name);m.diffuse_color=(*c,1);m.use_nodes=True
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Base Color'].default_value=(*c,1);p.inputs['Roughness'].default_value=rough;return m
cactusgreen=mat('Cactus skin',(.17,.28,.12));ribgreen=mat('Cactus ribs',(.12,.22,.09));spine=mat('Dry cream spines',(.58,.46,.28));branchmat=mat('Dry sage branches',(.20,.15,.085));leafmat=mat('Sage leaves',(.29,.33,.22))
parts=[]
def obj_mesh(name,v,f,m):
    me=bpy.data.meshes.new(name);me.from_pydata(v,[],f);me.update();o=bpy.data.objects.new(name,me);scene.collection.objects.link(o);o.data.materials.append(m);parts.append(o);return o
def sphere(name,loc,scale,m):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8,location=loc);o=bpy.context.object;o.name=name;o.scale=scale;o.data.materials.append(m);parts.append(o)
    for p in o.data.polygons:p.use_smooth=True
    return o
def beam(a,b,r,m):
    a,b=Vector(a),Vector(b);bpy.ops.mesh.primitive_cone_add(vertices=5,radius1=r,radius2=r*.3,depth=(b-a).length,location=(a+b)/2);o=bpy.context.object;o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();o.data.materials.append(m);parts.append(o)
def export_asset(name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:o.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]
    # Bake transforms so a shared origin is at the ground.
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);bpy.ops.object.join();o=parts[0];o.name=name
    bpy.ops.export_scene.gltf(filepath=BASE+'/godot-car/assets/'+name+'.glb',export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,export_cameras=False,export_lights=False)
    parts.clear();o.hide_set(True)
    return o
# Ribbed barrel cactus: rounded crown, yellow radial spines, weathered lower ribs.
v=[];faces=[];segments=96;rings=20
for j in range(rings+1):
    t=j/rings;z=.03+t*1.05;r=.36*math.sin(math.pi*(.13+.84*t))**.38
    for i in range(segments):
        a=i*math.tau/segments;rad=r*(1+.09*math.cos(a*12));v.append((rad*math.cos(a),rad*math.sin(a),z))
for j in range(rings):
    for i in range(segments):
        k=j*segments+i;n=j*segments+(i+1)%segments;faces.append((k,n,n+segments,k+segments))
faces.extend([tuple(range(segments-1,-1,-1)),tuple(rings*segments+i for i in range(segments))])
o=obj_mesh('Ribbed barrel cactus',v,faces,cactusgreen)
for p in o.data.polygons:p.use_smooth=True
for j in range(1,10):
    t=j/10;z=.03+t*1.05;r=.36*math.sin(math.pi*(.13+.84*t))**.38*1.09
    for i in range(12):
        a=i*math.tau/12;p=Vector((r*math.cos(a),r*math.sin(a),z));n=Vector((math.cos(a),math.sin(a),.2));tan=Vector((-math.sin(a),math.cos(a),0))
        for k in [-1,0,1]:beam(p,p+n*.07+tan*k*.035+Vector((0,0,k*.025)),.0035,spine)
barrel=export_asset('barrel_cactus')
# Prickly pear: branching oval pads with areoles and tiny spines.
for loc,scale,angle in [((0,0,.34),(.25,.09,.36),-.1),((.12,0,.86),(.27,.085,.37),-.15),((-.30,.02,.75),(.22,.08,.30),.65),((.40,.01,1.13),(.24,.07,.31),-.5),((-.4,.02,1.2),(.20,.075,.30),.12)]:
    o=sphere('Prickly pear pad',loc,scale,cactusgreen);o.rotation_euler.y=angle
    for zrow in [-.5,0,.5]:
        for xcol in [-.5,0,.5]:
            p=Vector(loc)+Vector((xcol*scale[0],-scale[1]*.94,zrow*scale[2]));sphere('Areole',p,(.012,.006,.012),spine)
            beam(p,p+Vector((.012,-.035,.018)),.0025,spine)
pear=export_asset('prickly_pear')
# Sagebrush: woody branching structure and hundreds of narrow matte leaves.
for i in range(15):
    a=i*math.tau/15+random.uniform(-.15,.15);end=Vector((math.cos(a)*random.uniform(.3,.55),math.sin(a)*random.uniform(.3,.55),random.uniform(.35,.7)))
    start=Vector((0,0,.04));beam(start,end,.013,branchmat)
    for j in range(3):
        t=.38+j*.23;p=start.lerp(end,t);tip=p+Vector((random.uniform(-.16,.16),random.uniform(-.16,.16),.22));beam(p,tip,.005,branchmat)
        for k in range(7):
            q=p.lerp(tip,(k+1)/8)+Vector((random.uniform(-.07,.07),random.uniform(-.07,.07),random.uniform(-.035,.035)))
            leaf=sphere('Sage leaf',q,(.018,.045,.009),leafmat);leaf.rotation_euler=(random.random()*2,random.random(),random.random()*math.tau)
shrub=export_asset('sagebrush')
# Save all editable workshop assets, at separated display locations.
for ob,x in [(barrel,-1.5),(pear,0),(shrub,1.5)]:ob.hide_set(False);ob.location.x=x
bpy.ops.wm.save_as_mainfile(filepath=BASE+'/desert_assets.blend')
print('DESERT_ASSETS_SAVED: 3 GLBs and 4 seamless textures')
