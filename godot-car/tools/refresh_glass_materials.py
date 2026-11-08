"""Refresh baked facade PBR maps in Blender; preserve the non-overlapping wall geometry."""
import bpy,numpy as np
from pathlib import Path
GLASS_ROOT=Path('/Users/dadorindmitrii/Documents/blender-top')
def refresh_city_glass():
    n=1024;yy,xx=np.mgrid[0:n,0:n]
    mask=(((xx/(n/4))%1>=1.1/3.6)&((xx/(n/4))%1<=3.1/3.6)&((yy/(n/4))%1<=2.1/3.8))
    def save(name,data,color=False):
        if data.ndim==2:data=np.repeat(data[:,:,None],3,axis=2)
        if color:data=np.where(data<=.0031308,data*12.92,1.055*np.maximum(data,0)**(1/2.4)-.055)
        im=bpy.data.images.new('_glass_refresh',width=n,height=n);im.colorspace_settings.name='Non-Color'
        im.pixels.foreach_set(np.concatenate([data,np.ones((n,n,1))],axis=2).astype(np.float32).ravel())
        path=GLASS_ROOT/'godot-car/textures'/(name+'.png');im.filepath_raw=str(path);im.file_format='PNG';im.save();bpy.data.images.remove(im)
        for image in bpy.data.images:
            if image.filepath and Path(bpy.path.abspath(image.filepath))==path:image.reload()
    save('city_window_mask',mask.astype(float))
    local_u=np.clip((((xx/(n/4))%1)-1.1/3.6)/(2.0/3.6),0,1)
    local_v=np.clip(((yy/(n/4))%1)/(2.1/3.8),0,1)
    save('city_window_data',np.stack([mask.astype(float),local_u*mask,local_v*mask],axis=2))
    for i in range(5):
        base=bpy.data.materials.get('City_Facade%d'%i)
        if base is None:continue
        rgb=np.broadcast_to(np.array(base.diffuse_color[:3]),(n,n,3)).copy()
        # Slightly tinted architectural glass with one neutral interior variation.
        rgb[mask]=(.025,.070,.095)
        warm=mask&(yy//256==2)&(xx//256==1)
        rgb[warm]=(.050,.065,.070)
        prefix='city_City_Facade%d'%i
        save(prefix+'_albedo',rgb,True)
        save(prefix+'_roughness',np.where(mask,.32,.85))
        save(prefix+'_metallic',np.zeros((n,n)))
        for mat in bpy.data.materials:
            if mat.name.startswith('City_Baked_City_Facade%d'%i):
                p=next(node for node in mat.node_tree.nodes if node.type=='BSDF_PRINCIPLED')
                p.inputs['IOR'].default_value=1.5
    print('GLASS_MAPS_REFRESHED: tinted dielectric glass, roughness 0.32, metallic 0; mask saved')
refresh_city_glass()
