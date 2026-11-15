extends SceneTree
func _initialize():call_deferred('run')
func run():
 var args:=OS.get_cmdline_user_args()
 var destination:String=args[0] if args.size()>0 else ProjectSettings.globalize_path('user://palm_bay_base.glb')
 var world=load('res://palm_bay.tscn').instantiate()
 world.use_exported_model=false
 root.add_child(world)
 var geometry=world.get_node('ArtGeometry')
 for node in geometry.get_children():
  if node is Label3D:
   var mesh:=TextMesh.new()
   mesh.text=node.text;mesh.font_size=node.font_size;mesh.pixel_size=node.pixel_size
   mesh.depth=.035
   var replacement:=MeshInstance3D.new()
   replacement.name='Sign_'+node.text.replace(' ','_')
   replacement.mesh=mesh
   replacement.material_override=world.materials.white
   replacement.transform=node.transform
   geometry.add_child(replacement)
   geometry.remove_child(node);node.queue_free()
 var state:=GLTFState.new()
 var document:=GLTFDocument.new()
 var error:=document.append_from_scene(geometry,state)
 if error!=OK:push_error('GLTF append failed '+str(error));quit(1);return
 error=document.write_to_filesystem(state,destination)
 if error!=OK:push_error('GLTF write failed '+str(error));quit(1);return
 var metadata:={'palm_count':world.palm_count,'building_count':world.building_count,'pool_count':world.pool_count,'colliders':[]}
 for body in world.collisions.get_children():
  var size:Vector3=body.get_child(0).shape.size
  metadata.colliders.append({'position':[body.position.x,body.position.y,body.position.z],'size':[size.x,size.y,size.z],'yaw':body.rotation.y})
 var file:=FileAccess.open(destination.get_basename()+'.json',FileAccess.WRITE)
 file.store_string(JSON.stringify(metadata,'  '));file.close()
 print('PALM_BASE_EXPORTED ',destination,' vertices from ',geometry.get_child_count(),' batches; colliders=',metadata.colliders.size())
 world.queue_free();await process_frame;quit()
