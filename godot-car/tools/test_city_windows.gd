extends SceneTree
var failed:=false
func check(ok:bool,description:String):
    print("PASS " if ok else "FAIL ",description)
    if not ok:failed=true
func _initialize():call_deferred("run")
func run():
    var city=load("res://city.tscn").instantiate()
    root.add_child(city)
    var overlays:=0
    var facade_surfaces:=0
    var glass_surfaces:=0
    var materials:Dictionary={}
    for ob in city.find_children("Block_*","MeshInstance3D",true,false):
        for index in ob.mesh.get_surface_count():
            var material=ob.mesh.surface_get_material(index)
            if material.resource_name.begins_with("City_Baked"):
                facade_surfaces+=1
                materials[material.resource_name]=material
                var glass:=ob.get_surface_override_material(index) as ShaderMaterial
                if glass and glass.shader.resource_path.ends_with("city_glass_facade.gdshader"):glass_surfaces+=1
            if material.resource_name.begins_with("City_Blue glass") or material.resource_name.begins_with("City_Warm glass"):
                var arrays:Array=ob.mesh.surface_get_arrays(index)
                var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
                var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
                for i in range(0,indices.size(),3):
                    if minf(vertices[indices[i]].y,minf(vertices[indices[i+1]].y,vertices[indices[i+2]].y))>6.0:overlays+=1
    check(glass_surfaces==facade_surfaces,"glass shading is applied only to facade surfaces")
    var mask:Texture2D=load("res://textures/city_window_mask.png")
    check(mask.get_image().has_mipmaps(),"glass mask is filtered at distance")
    for region in ["north","south"]:
        var reflection:Texture2D=load("res://textures/city_reflection_"+region+".png")
        check(reflection.get_size()==Vector2(768,512) and reflection.get_image().has_mipmaps(),region+" reflection atlas has six filtered faces")
    check(not city.has_node("GlassReflections"),"reflection atlases need no runtime capture")
    check(overlays==0,"no separate window triangles remain above ground-floor glazing")
    check(facade_surfaces>=100 and materials.size()==5,"all five facade finishes use baked opaque window textures")
    for name in materials:
        var material:StandardMaterial3D=materials[name]
        check(material.albedo_texture!=null and material.albedo_texture.get_image().has_mipmaps(),name+" has real mipmaps")
        check(material.texture_filter==BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC,name+" uses anisotropic mip filtering")
    city.queue_free()
    await process_frame
    print("CITY_WINDOW_TESTS_DONE")
    quit(1 if failed else 0)
