"""Reusable Blender city dressing; preserves the existing architecture and window UVs."""
import ast, bpy, bmesh, math, random, json
from pathlib import Path
from mathutils import Vector
ENRICH_ROOT=Path('/Users/dadorindmitrii/Documents/blender-top')

def enrich_city(scene,root,metadata):
    rng=random.Random(71211)
    source=(ENRICH_ROOT/'godot-car/tools/build_city_blender.py').read_text()
    batch_ast=next(n for n in ast.parse(source).body if isinstance(n,ast.ClassDef) and n.name=='Batch')
    materials=list(next(ob for ob in root.children if ob.name.split('.')[0]=='StreetFurniture').data.materials)
    def mat(name,color,metal=0,rough=.7):
        full='City_'+name
        m=bpy.data.materials.get(full) or bpy.data.materials.new(full)
        m.use_nodes=True;m.diffuse_color=(*color,1)
        p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal
        if m not in materials:materials.append(m)
        return materials.index(m)
    def existing(name):return next(i for i,m in enumerate(materials) if m.name.split('.')[0]=='City_'+name)
    asphalt=existing('Asphalt');black=existing('Street metal');chrome=existing('Metal');glass=existing('Blue glass');red=existing('Terracotta');blue=existing('Store blue');white=existing('Road white')
    env=dict(Vector=Vector,math=math,bpy=bpy,materials=materials,scene=scene,root=root,asphalt=asphalt)
    exec(compile(ast.Module(body=[batch_ast],type_ignores=[]),'Batch','exec'),env)
    Batch=env['Batch']
    # Rebuild the original street furniture without its crude box-shaped cars.
    metadata['colliders']=[c for c in metadata['colliders'] if c.get('source')!='city_life' and c['size']!=[1.9,1.5,4.2]]
    metadata['signals']=[]
    for ob in list(root.children):
        if ob.name.split('.')[0]=='StreetFurniture' or ob.name.startswith('Enriched_'):bpy.data.objects.remove(ob,do_unlink=True)
    street_source=source[source.index('street=Batch()'):source.index("# Readable street names")]
    a=street_source.index('  if random.random()<.65:');b=street_source.index('# Four functioning',a)
    street_source=street_source[:a]+street_source[b:]
    env.update(metadata=metadata,random=rng,black=black,chrome=chrome,glass=glass,red=red,blue=blue,white=white)
    exec(compile(street_source,'street_furniture','exec'),env)
    paint=[mat('Car '+name,c,.55,.24) for name,c in [('Ivory',(.78,.76,.65)),('Red',(.58,.045,.025)),('Teal',(.025,.32,.29)),('Gold',(.62,.39,.045)),('Navy',(.035,.07,.16)),('Silver',(.46,.51,.55)),('Green',(.12,.22,.09)),('White',(.85,.87,.85)),('Graphite',(.065,.075,.085))]]
    for index in paint:
        node=next(n for n in materials[index].node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        node.inputs['Coat Weight'].default_value=.35
        node.inputs['Coat Roughness'].default_value=.18
    tire=mat('Rubber',(.018,.021,.023),0,.95);car_glass=mat('Car glazing',(.035,.09,.13),.42,.16)
    lamp=mat('Headlamps',(.8,.85,.76),.2,.22);tail=mat('Tail lamps',(.65,.018,.012),.2,.24)
    lawn=mat('Lawn',(.15,.28,.08));soil=mat('Tree soil',(.10,.075,.045));bark=mat('Broadleaf bark',(.22,.15,.085))
    leaves=[mat('Broadleaf '+str(i),c) for i,c in enumerate([(.12,.26,.065),(.20,.34,.09),(.08,.21,.06)])]
    edging=mat('Planter stone',(.42,.44,.40));bin_green=mat('Wheelie green',(.035,.18,.10),.08,.65);bin_blue=mat('Recycling blue',(.025,.14,.30),.1,.6)
    detail={"__name__":"city_realism"}
    exec(compile((ENRICH_ROOT/'godot-car/tools/city_realism_geometry.py').read_text(),'city_realism_geometry.py','exec'),detail)
    car_builder=detail['RealisticCars'](Batch,materials)
    plate=mat('Car number plates',(.73,.75,.70),0,.45)
    brake=mat('Brake steel',(.11,.12,.125),.65,.42)
    car_mats=dict(black=black,chrome=chrome,glass=car_glass,rubber=tire,lamp=lamp,tail=tail,plate=plate,brake=brake)
    car_batches=[Batch() for _ in range(4)]
    green=Batch();props=Batch()
    def finish(batch,name,smooth=False):
        ob=batch.save(name)
        if smooth:
            bm=bmesh.new();bm.from_mesh(ob.data)
            bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00005)
            bm.to_mesh(ob.data);bm.free()
            for poly in ob.data.polygons:poly.use_smooth=True
            ob.data.set_sharp_from_angle(angle=math.radians(38))
            ob.data.update()
        return ob
    def collision(pos,size):metadata['colliders'].append(dict(position=list(pos),size=list(size),source='city_life'))
    def car(x,z,yaw,kind,color):
        group=(1 if x>0 else 0)+(2 if z>0 else 0)
        car_builder.add(car_batches[group],x,z,yaw,kind,color,car_mats)
        length=[2.15,1.85,2.3][kind]
        collision((x,.83,z),(1.98,1.55,2*length) if abs(math.sin(yaw))<.5 else (2*length,1.55,1.98))
    car_count=0
    for axis in metadata['streets']:
        for mid in [-400,-240,-80,80,240,400]:
            for side in [-1,1]:
                if rng.random()<.10:continue
                for horizontal in [False,True]:
                    coord=mid+rng.choice([-32,26])+rng.uniform(-7,7)
                    x,z=(coord,axis+side*5.5) if horizontal else (axis+side*5.5,coord)
                    yaw=(math.pi/2 if horizontal else 0)+(math.pi if side<0 else 0)
                    car(x,z,yaw,rng.randrange(3),rng.choice(paint));car_count+=1
    # A few clearly visible examples near the starting district.
    for x,z,kind,color in [(5.5,375,0,paint[1]),(5.5,402,1,paint[2]),(-5.5,364,2,paint[3]),(-5.5,410,0,paint[0])]:
        car(x,z,0 if x>0 else math.pi,kind,color);car_count+=1
    for i,batch in enumerate(car_batches):
        finish(batch,'Enriched_ParkedCars'+('' if i==0 else '_'+str(i)),True)
    def tree(x,z):
        height=rng.uniform(4.7,6.4);r=rng.uniform(1.4,2.1)
        detail['add_tree'](green,x,z,height,r,rng.getrandbits(32),dict(bark=bark,leaves=leaves))
        collision((x,1.1,z),(.45,1.8,.45))
    def bin(x,z,color):
        props.box((x,.70,z),(.74,.94,.70),color);props.box((x,1.2,z),(.81,.09,.78),black)
        props.box((x,.99,z+.37),(.5,.11,.025),white)
        props.beam((x-.4,.34,z+.27),(x+.4,.34,z+.27),.13,tire,8)
        props.box((x,1.04,z-.37),(.55,.07,.10),black)
        collision((x,.72,z),(.84,1.15,.86))
    trees=lawns=bins=0
    for ix in range(6):
        for iz in range(6):
            mx=-400+160*ix;mz=-400+160*iz
            green=Batch()
            # Planting strips between carriageway and the existing buildings.
            for side in [-1,1]:
                for along in [-31,23]:
                    x=mx+side*65;z=mz+along
                    green.box((x,.235,z),(4.8,.11,27),edging)
                    green.box((x,.30,z),(4.35,.035,26.55),lawn);lawns+=1
                    for dz in [-8,8]:
                        green.box((x,.326,z+dz),(1.1,.025,1.1),soil);tree(x,z+dz);trees+=1
                for off,color in [(7,bin_green),(8.2,bin_blue)]:bin(mx+side*61,mz+off,color);bins+=1
            if (ix,iz) in [(1,4),(4,1),(4,4)]:
                for dx in [-36,0,36]:
                    for dz in [-28,28]:tree(mx+dx,mz+dz);trees+=1
            finish(green,'Enriched_Landscaping'+('' if ix==0 and iz==0 else '_%d_%d'%(ix,iz)),True)
    props.save('Enriched_Bins')
    metadata['city_life']={'parked_cars':car_count,'trees':trees,'lawns':lawns,'bins':bins,'version':2}
    print('CITY_ENRICHED',metadata['city_life'])

if __name__=='__main__':
    scene=bpy.context.scene;root=bpy.data.objects['PacificCity']
    metadata=json.loads((ENRICH_ROOT/'godot-car/assets/pacific_city.json').read_text())
    enrich_city(scene,root,metadata)
    bpy.ops.object.select_all(action='DESELECT');root.select_set(True)
    for ob in root.children:ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(ENRICH_ROOT/'godot-car/assets/pacific_city.glb'),export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,export_cameras=False,export_lights=False)
    (ENRICH_ROOT/'godot-car/assets/pacific_city.json').write_text(json.dumps(metadata))
    bpy.ops.wm.save_as_mainfile(filepath=str(ENRICH_ROOT/'pacific_city.blend'))
