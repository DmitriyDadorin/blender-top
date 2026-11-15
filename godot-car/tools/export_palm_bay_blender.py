"""Blender: prepare a Palm Bay source scene, or re-export the edited .blend.

Build from the generated base:
  Blender --background --python export_palm_bay_blender.py -- --source-glb /tmp/palm_bay_base.glb --metadata /tmp/palm_bay_base.json
Re-export manual edits:
  Blender --background palm_bay.blend --python export_palm_bay_blender.py
"""
import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "godot-car" / "assets"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source-glb", type=Path)
parser.add_argument("--metadata", type=Path)
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])

def point(value):
    """Godot Y-up to Blender Z-up, consistent with the glTF importer."""
    x, y, z = value
    return Vector((x, -z, y))

def material(name):
    return bpy.data.materials.get("PalmBay_" + name)

def tube(name, coords, radius, mat, collection):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 3
    spline = curve.splines.new("POLY")
    spline.points.add(len(coords) - 1)
    for vertex, coord in zip(spline.points, coords):
        vertex.co = (*point(coord), 1)
    ob = bpy.data.objects.new(name, curve)
    collection.objects.link(ob)
    if mat:curve.materials.append(mat)
    return ob

if args.source_glb:
    if not args.metadata:parser.error("--source-glb requires --metadata")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.name = "PalmBay_Resort"
    bpy.ops.import_scene.gltf(filepath=str(args.source_glb), merge_vertices=True)
    art = bpy.data.collections.new("Palm Bay | Editable geometry")
    scene.collection.children.link(art)
    for ob in list(scene.objects):
        for collection in list(ob.users_collection):collection.objects.unlink(ob)
        art.objects.link(ob)
    metadata = json.loads(args.metadata.read_text())
    scene["palm_count"] = metadata["palm_count"]
    scene["building_count"] = metadata["building_count"]
    scene["pool_count"] = metadata["pool_count"]
    scene["description"] = "Original sunlit seaside resort: pool terraces, white architecture, palms and an ocean boulevard."
    scene["Godot scene"] = "godot-car/palm_bay.tscn"
    scene["Source palette"] = "White / coral / turquoise / cobalt / palm green"
    collision_collection = bpy.data.collections.new("Collisions | Box proxies")
    scene.collection.children.link(collision_collection)
    for index, entry in enumerate(metadata["colliders"]):
        bpy.ops.mesh.primitive_cube_add(size=1, location=point(entry["position"]))
        ob = bpy.context.object
        ob.name = "COLLISION_%03d" % index
        sx, sy, sz = entry["size"]
        ob.dimensions = (sx, sz, sy)
        ob.rotation_euler.z = entry["yaw"]
        ob.display_type = "WIRE"
        ob.hide_render = True
        ob.hide_set(True)
        for collection in list(ob.users_collection):collection.objects.unlink(ob)
        collision_collection.objects.link(ob)
    collision_collection.hide_render = True
    # Poolside details are built and remain editable in Blender.
    for z in [219.0, 254.0]:
        for dz in [0.0, .9]:
            tube("Pool ladder rail", [(-249.6, .2, z+dz), (-249.6, 1.0, z+dz), (-250.0, 1.2, z+dz), (-250.8, 1.0, z+dz), (-251.8, -.2, z+dz)], .045, material("white"), art)
    for z in [-190.0, 150.0]:
        tube("Promenade shower", [(-346, .05, z), (-346, 2.8, z), (-345.7, 3.05, z), (-345.2, 3.05, z)], .065, material("white"), art)
    studio = bpy.data.collections.new("Studio | Camera and sun")
    scene.collection.children.link(studio)
    camera_data = bpy.data.cameras.new("Poolside postcard")
    camera = bpy.data.objects.new("Poolside postcard", camera_data)
    studio.objects.link(camera)
    camera.location = point((-229, 7, 286))
    target = point((-282, 3, 233))
    camera.rotation_euler = (target-camera.location).to_track_quat("-Z", "Y").to_euler()
    camera_data.lens = 29
    camera_data.clip_end = 20000
    scene.camera = camera
    sun_data = bpy.data.lights.new("Summer sun", "SUN")
    sun_data.energy = 2.2
    sun_data.color = (1.0, .64, .38)
    sun_data.angle = math.radians(.8)
    sun = bpy.data.objects.new("Summer sun", sun_data)
    studio.objects.link(sun)
    sun.rotation_euler = Vector((.904, -.329, -.276)).to_track_quat("-Z", "Y").to_euler()
    scene.world = bpy.data.worlds.new("Sunset rose")
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (.45, .25, .37, 1)
    background.inputs["Strength"].default_value = .24
    scene.unit_settings.system = "METRIC"
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 48
    scene.render.resolution_x = 1100
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "Standard"
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type != "VIEW_3D":continue
            space = area.spaces.active
            space.clip_end = 20000
            space.overlay.show_overlays = False
            space.shading.type = "MATERIAL"
            space.shading.use_scene_world = True
            space.shading.use_scene_lights = True
            space.region_3d.view_location = target
            space.region_3d.view_rotation = camera.rotation_euler.to_quaternion()
            space.region_3d.view_distance = 75
            space.region_3d.view_perspective = "CAMERA"

scene = bpy.context.scene
collision_collection = bpy.data.collections.get("Collisions | Box proxies")
if collision_collection is None:raise RuntimeError("Open palm_bay.blend or pass --source-glb and --metadata")
metadata = {key: int(scene[key]) for key in ["palm_count", "building_count", "pool_count"]}
metadata["colliders"] = []
for ob in collision_collection.objects:
    x, y, z = ob.location
    sx, sy, sz = ob.dimensions
    metadata["colliders"].append({"position": [x, z, -y], "size": [sx, sz, sy], "yaw": ob.rotation_euler.z})
ASSETS.mkdir(parents=True, exist_ok=True)
(ASSETS / "palm_bay.json").write_text(json.dumps(metadata, indent=2))
bpy.ops.object.select_all(action="DESELECT")
for collection in bpy.data.collections:
    if collection.name.startswith("Palm Bay |"):
        for ob in collection.all_objects:
            ob.hide_set(False)
            ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(ASSETS / "palm_bay.glb"), export_format="GLB", use_selection=True, export_yup=True, export_apply=True, export_cameras=False, export_lights=False, export_extras=True)
bpy.ops.object.select_all(action="DESELECT")
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "palm_bay.blend"))
print("PALM_BAY_BLENDER_EXPORTED", ROOT / "palm_bay.blend", ASSETS / "palm_bay.glb", "colliders", len(metadata["colliders"]))
