"""Local-space car templates and irregular broadleaf trees for Blender batches."""
import bpy, bmesh, math, random
from mathutils import Vector

class RealisticCars:
    def __init__(self,Batch,materials):
        self.Batch=Batch;self.materials=materials;self.body_cache={}
    def body(self,kind,paint):
        if kind in self.body_cache:return self.body_cache[kind]
        L=[2.15,1.85,2.30][kind];wheelbase=L*.63
        sections=[(-L,.71,.38,.77),(-L+.23,.85,.28,.94),(-wheelbase,.91,.27,1.01),(-.77,.90,.26,1.02),(.5,.89,.26,.99),(wheelbase,.91,.27,1.00),(L-.22,.84,.32,.94),(L,.73,.42,.83)]
        batch=self.Batch();rings=[]
        for z,w,low,top in sections:
            rings.append([(-w*.8,low,z),(-w,low+.08,z),(-w,top-.09,z),(-w*.9,top,z),(w*.9,top,z),(w,top-.09,z),(w,low+.08,z),(w*.8,low,z)])
        for a,b in zip(rings,rings[1:]):
            for j in range(8):k=(j+1)%8;batch.face([a[j],a[k],b[k],b[j]],paint)
        batch.face(rings[0][::-1],paint);batch.face(rings[-1],paint)
        ob=batch.save('RealismTempBody')
        for z in [-wheelbase,wheelbase]:
            bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=.392,depth=3,location=(0,-z,.39),rotation=(0,math.pi/2,0))
            cutter=bpy.context.object
            mod=ob.modifiers.new('Wheel arch cut','BOOLEAN');mod.object=cutter
            bpy.context.view_layer.objects.active=ob
            bpy.ops.object.modifier_apply(modifier=mod.name)
            bpy.data.objects.remove(cutter,do_unlink=True)
        mod=ob.modifiers.new('Soft body edges','BEVEL');mod.width=.022;mod.segments=2
        deps=bpy.context.evaluated_depsgraph_get()
        mesh=bpy.data.meshes.new_from_object(ob.evaluated_get(deps),depsgraph=deps)
        geometry=[[(mesh.vertices[i].co.x,mesh.vertices[i].co.z,-mesh.vertices[i].co.y) for i in f.vertices] for f in mesh.polygons]
        bpy.data.meshes.remove(mesh);bpy.data.objects.remove(ob,do_unlink=True)
        self.body_cache[kind]=geometry
        return geometry
    def add(self,batch,x,z,yaw,kind,paint,m):
        L=[2.15,1.85,2.30][kind];axle=L*.63
        def point(p):
            a,y,b=p;return(x+a*math.cos(yaw)+b*math.sin(yaw),y,z-a*math.sin(yaw)+b*math.cos(yaw))
        def face(points,mat):batch.face([point(p) for p in points],mat)
        def box(p,size,mat):
            q=self.Batch();q.box(p,size,mat)
            for f,mi in zip(q.f,q.m):face([(q.v[i][0],q.v[i][2],-q.v[i][1]) for i in f],mi)
        def beam(a,b,r,mat,sides=8,r2=None):batch.beam(point(a),point(b),r,mat,sides,r2)
        def line(points,r,mat):
            for a,b in zip(points,points[1:]):beam(a,b,r,mat,6)
        for points in self.body(kind,paint):face(points,paint)
        black=m['black'];glass=m['glass'];chrome=m['chrome'];rubber=m['rubber']
        # A closed glass cabin with separate roof and accurately sloping front/rear glass.
        rear=[1.17,1.43,1.85][kind];roof_rear=[.65,.92,1.40][kind];roof_h=[1.49,1.53,1.52][kind]
        bottom=[(-.79,1.01,-1.08),(.79,1.01,-1.08),(.80,1.01,rear),(-.80,1.01,rear)]
        top=[(-.67,roof_h,-.48),(.67,roof_h,-.48),(.67,roof_h,roof_rear),(-.67,roof_h,roof_rear)]
        for j in range(4):k=(j+1)%4;face([bottom[j],bottom[k],top[k],top[j]],glass)
        face([(a,y+.035,b) for a,y,b in top],paint)
        for side in [-1,1]:
            lower=[(side*.795,1.025,-1.08),(side*.805,1.025,rear)]
            upper=[(side*.677,roof_h+.01,-.48),(side*.677,roof_h+.01,roof_rear)]
            line([lower[0],upper[0],upper[1],lower[1],lower[0]],.021,black)
            beam(lower[0],upper[0],.032,paint);beam(lower[1],upper[1],.032,paint)
            beam((side*.80,1.02,.32),(side*.677,roof_h,.32),.026,black)
            # Door seams, handles, mirror stalks and housing.
            line([(side*.895,1.0,-.70),(side*.905,.65,-.72),(side*.905,.48,-.58),(side*.90,.48,.95),(side*.895,.96,1.0)],.0045,black)
            box((side*.908,.93,.68),(.026,.04,.19),chrome)
            beam((side*.80,1.10,-.82),(side*.96,1.13,-.83),.02,black)
            box((side*1.005,1.15,-.83),(.17,.13,.23),paint)
            box((side*1.007,1.15,-.705),(.135,.082,.009),chrome)
            box((side*.88,.34,.0),(.055,.07,axle*1.05),black)
            for zz in [-axle,axle]:
                # Rounded tire cross section rather than a flat-sided cylinder.
                rings=[]
                for offset,radius in [(-.105,.285),(-.09,.34),(-.055,.36),(.055,.36),(.09,.34),(.105,.285)]:
                    rings.append([(side*.875+offset,.39+radius*math.sin(i*math.tau/24),zz+radius*math.cos(i*math.tau/24)) for i in range(24)])
                for a,b in zip(rings,rings[1:]):
                    for j in range(24):k=(j+1)%24;face([a[j],a[k],b[k],b[j]],rubber)
                outside=side*.984
                beam((outside-side*.018,.39,zz),(outside,.39,zz),.252,black,24)
                beam((outside+side*.005,.39,zz),(outside+side*.009,.39,zz),.20,m['brake'],24)
                for j in range(5):
                    a=j*math.tau/5+.15
                    beam((outside+side*.015,.39+.065*math.sin(a),zz+.065*math.cos(a)),(outside+side*.015,.39+.235*math.sin(a+.16),zz+.235*math.cos(a+.16)),.022,chrome,6)
                beam((outside+side*.018,.39,zz),(outside+side*.029,.39,zz),.066,chrome,12)
                # A painted arch lip follows the opening above the tire.
                points=[(side*.916,.39+.398*math.sin(a*math.pi/16),zz+.398*math.cos(a*math.pi/16)) for a in range(17)]
                line(points,.012,paint)
            box((side*.57,.77,-L-.006),(.39,.17,.045),black)
            for offset in [-.09,.09]:beam((side*.57+offset,.79,-L-.033),(side*.57+offset,.79,-L-.047),.054,m['lamp'],12)
            box((side*.57,.70,-L-.04),(.35,.018,.014),m['lamp'])
            box((side*.59,.79,L-.015),(.41,.09,.034),m['tail'])
            box((side*.57,.79,L+.005),(.29,.016,.008),m['lamp'])
        box((0,.57,-L-.012),(.75,.21,.045),black)
        for h in [.51,.57,.63]:box((0,h,-L-.04),(.69,.012,.016),chrome)
        box((0,.36,-L+.035),(1.48,.09,.10),black)
        box((0,.39,L-.03),(1.47,.10,.08),black)
        box((0,.64,L+.012),(.34,.13,.012),m['plate'])
        # Fine hood and trunk lines remain geometric and stable at distance.
        line([(-.55,.965,-L+.26),(-.66,1.035,-.78),(.66,1.035,-.78),(.55,.965,-L+.26)],.0035,black)

def add_tree(batch,x,z,height,radius,seed,m):
    rng=random.Random(seed)
    bark=m['bark'];leaves=m['leaves']
    lean=Vector((rng.uniform(-.25,.25),0,rng.uniform(-.25,.25)))
    origin=Vector((x,.32,z));trunk_top=origin+Vector((0,height-.8,0))+lean
    mid=origin+Vector((0,height*.52,0))+lean*.4
    batch.beam(origin,mid,.17,bark,10,.105)
    batch.beam(mid,trunk_top,.105,bark,9,.045)
    # Foliage is made of clusters of small folded leaves. Empty space between
    # branches gives a broken silhouette and lets sunlight reach the pavement.
    for branch in range(9):
        angle=branch*2.39996+rng.uniform(-.3,.3)
        base=origin+Vector((0,height*.45+branch*.13,0))+lean*.4
        reach=radius*rng.uniform(.45,.92)
        end=trunk_top+Vector((math.cos(angle)*reach,rng.uniform(-.85,.65),math.sin(angle)*reach))
        elbow=base.lerp(end,.53)+Vector((0,.22,0))
        batch.beam(base,elbow,.055,bark,7,.028);batch.beam(elbow,end,.028,bark,6,.009)
        for twig in [-1,1]:
            tip=end+Vector((math.cos(angle+twig*.8)*.40,.20,math.sin(angle+twig*.8)*.40))
            batch.beam(elbow,tip,.016,bark,5,.004)
        for i in range(80):
            az=rng.uniform(0,math.tau);up=rng.uniform(-1,1);rr=rng.random()**(1/3)
            spread=Vector((math.sqrt(1-up*up)*math.cos(az),up*.72,math.sqrt(1-up*up)*math.sin(az)))*radius*.59*rr
            center=end+spread
            normal=Vector((rng.uniform(-1,1),rng.uniform(-.25,1),rng.uniform(-1,1))).normalized()
            tangent=normal.cross(Vector((0,0,1)))
            if tangent.length<.05:tangent=Vector((1,0,0))
            tangent.normalize();side=normal.cross(tangent).normalized()
            length=rng.uniform(.105,.17);width=length*rng.uniform(.38,.60)
            points=[center-tangent*length,center-side*width,center+tangent*length,center+side*width]
            ridge=center+normal*.012
            mat=rng.choice(leaves)
            for j in range(4):batch.face([ridge,points[j],points[(j+1)%4]],mat)
