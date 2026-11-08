extends SceneTree
func _initialize():call_deferred("run")
func capture():
    for i in 4:await process_frame
    await RenderingServer.frame_post_draw
    return root.get_texture().get_image()
func run():
    var world:=Node3D.new()
    root.add_child(world)
    var mat:=ShaderMaterial.new()
    mat.shader=load("res://materials/city_glass_facade.gdshader")
    mat.set_shader_parameter("facade_albedo",load("res://assets/pacific_city_city_City_Facade0_albedo.png"))
    mat.set_shader_parameter("window_mask",load("res://textures/city_window_mask.png"))
    mat.set_shader_parameter("window_data",load("res://textures/city_window_data.png"))
    var wall:=MeshInstance3D.new()
    var quad:=QuadMesh.new()
    quad.size=Vector2(20,20)
    wall.mesh=quad
    wall.material_override=mat
    wall.position.y=25
    world.add_child(wall)
    var sun:=DirectionalLight3D.new()
    sun.rotation_degrees=Vector3(-47,-32,0)
    sun.light_energy=.95
    world.add_child(sun)
    var environment:=WorldEnvironment.new()
    var env:=Environment.new()
    env.background_mode=Environment.BG_COLOR
    env.background_color=Color(.25,.35,.5)
    env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color=Color(.8,.85,.9)
    env.ambient_light_energy=.45
    env.reflected_light_source=Environment.REFLECTION_SOURCE_DISABLED
    environment.environment=env
    world.add_child(environment)
    var camera:=Camera3D.new()
    camera.current=true
    camera.fov=45
    world.add_child(camera)
    var point:=Vector3(2.915,26.38,0)
    var light_direction:=sun.global_basis.z
    var normal:=Vector3.BACK
    var reflection:=2*normal*normal.dot(light_direction)-light_direction
    camera.position=point+reflection*32
    camera.look_at(point)
    var lit:Image=await capture()
    mat.set_shader_parameter("glass_specular",0.0)
    var matte:Image=await capture()
    var count:=0
    var total:=0.0
    var peak:=0.0
    for y in range(0,lit.get_height(),3):
        for x in range(0,lit.get_width(),3):
            var a:=lit.get_pixel(x,y)
            var b:=matte.get_pixel(x,y)
            var delta:=maxf(0, (a.r+a.g+a.b-b.r-b.g-b.b)/3.0)
            peak=maxf(peak,delta)
            total+=delta
            if delta>.03:count+=1
    print("SUN_GLASS_RESPONSE peak=",peak," changed_samples=",count," total=",total)
    quit(0 if count>30 and peak>.05 else 1)
