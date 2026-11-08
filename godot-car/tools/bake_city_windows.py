"""Blender repair: bake window panels into opaque facade textures, with no depth overlap."""
import bpy, bmesh, numpy as np
from pathlib import Path
WINDOWS_ROOT=Path('/Users/dadorindmitrii/Documents/blender-top')

def bake_city_windows():
    scene=bpy.context.scene
    textures=WINDOWS_ROOT/'godot-car/textures'
    city=next(o for o in scene.objects if o.type=='EMPTY' and o.name.startswith('PacificCity'))
    material_cache={}
    removed=0;walls=0
    def srgb(value):
        return np.where(value<=.0031308,value*12.92,1.055*np.maximum(value,0)**(1/2.4)-.055)
    def image(name,data):
        h,w,_=data.shape
        im=bpy.data.images.new(name,width=w,height=h)
        im.colorspace_settings.name='Non-Color'
        im.pixels.foreach_set(np.concatenate([data,np.ones((h,w,1))],axis=2).astype(np.float32).ravel())
        im.filepath_raw=str(textures/(name+'.png'));im.file_format='PNG';im.save()
        # Color images are stored as encoded sRGB, data images remain non-color.
        if 'albedo' in name:im.colorspace_settings.name='sRGB'
        return im
    def facade(base):
        key=base.name
        if key in material_cache:return material_cache[key]
        n=1024
        yy,xx=np.mgrid[0:n,0:n]
        ux=(xx/(n/4))%1;vy=(yy/(n/4))%1
        mask=(ux>=1.1/3.6)&(ux<=3.1/3.6)&(vy<=2.1/3.8)
        color=np.array(base.diffuse_color[:3])
        rgb=np.broadcast_to(color,(n,n,3)).copy()
        rgb[mask]=(.025,.070,.095)
        warm=np.zeros((n,n),dtype=bool)
        warm[(yy//256==2)&(xx//256==1)]=True
        rgb[mask&warm]=(.050,.065,.070)
        albedo=image('city_'+key+'_albedo',srgb(rgb))
        rough=np.where(mask,.32,.85)
        rough_image=image('city_'+key+'_roughness',np.repeat(rough[:,:,None],3,axis=2))
        metal=np.zeros((n,n))
        metal_image=image('city_'+key+'_metallic',np.repeat(metal[:,:,None],3,axis=2))
        mat=bpy.data.materials.new('City_Baked_'+key)
        mat.use_nodes=True;mat.diffuse_color=base.diffuse_color
        p=next(node for node in mat.node_tree.nodes if node.type=='BSDF_PRINCIPLED')
        p.inputs['Base Color'].default_value=(1,1,1,1)
        for source,socket in [(albedo,'Base Color'),(rough_image,'Roughness'),(metal_image,'Metallic')]:
            node=mat.node_tree.nodes.new('ShaderNodeTexImage');node.image=source;node.interpolation='Linear'
            mat.node_tree.links.new(node.outputs['Color'],p.inputs[socket])
        material_cache[key]=mat
        return mat
    for ob in city.children:
        if ob.type!='MESH' or not ob.name.startswith('Block_'):continue
        mesh=ob.data
        bm=bmesh.new();bm.from_mesh(mesh);bm.normal_update()
        panels=[];wall_faces=[]
        for f in bm.faces:
            m=mesh.materials[f.material_index]
            if m.name.startswith(('City_Blue glass','City_Warm glass')) and len(f.verts)==4 and min(v.co.z for v in f.verts)>6.0:
                panels.append(f)
            if m.name.startswith('City_Facade') and abs(f.normal.z)<.1:
                height=max(v.co.z for v in f.verts)-min(v.co.z for v in f.verts)
                if height>10:wall_faces.append((f,m))
        if not panels and not wall_faces:
            bm.free();continue
        removed+=len(panels)
        bmesh.ops.delete(bm,geom=panels,context='FACES')
        uv=bm.loops.layers.uv.active or bm.loops.layers.uv.new('UVMap')
        for f,base in wall_faces:
            mat=facade(base)
            if mat.name not in mesh.materials:mesh.materials.append(mat)
            f.material_index=mesh.materials.find(mat.name)
            use_y=abs(f.normal.x)>.5
            coords=[-v.co.y if use_y else v.co.x for v in f.verts]
            low=min(coords)
            for loop in f.loops:
                frontage=-loop.vert.co.y if use_y else loop.vert.co.x
                loop[uv].uv=((frontage-low)/(4*3.6),(loop.vert.co.z-2.3)/(4*3.8))
            walls+=1
        bm.to_mesh(mesh);bm.free();mesh.update()
    print('WINDOWS_BAKED',removed,'overlay quads removed;',walls,'facades use filtered textures')
    return removed,walls

bake_city_windows()
exec(compile(open(str(WINDOWS_ROOT/'godot-car/tools/refresh_glass_materials.py')).read(), 'refresh_glass_materials.py', 'exec'))
