"""Repair the imported city's closed road/paint boxes without moving geometry.

Run: Blender --background pacific_city.blend --python this_script.py
"""
import shutil
from pathlib import Path

import bmesh
import bpy

ROOT = Path(__file__).resolve().parents[2]
source = ROOT / "pacific_city.blend"
asset = ROOT / "godot-car" / "assets" / "pacific_city.glb"
backup = ROOT / "build" / "crosswalk-original"
backup.mkdir(parents=True, exist_ok=True)
for path in [source, asset]:
    if not (backup / path.name).exists():
        shutil.copy2(path, backup / path.name)

street = bpy.data.objects["StreetNetwork"]
mesh = street.data
bm = bmesh.new()
bm.from_mesh(mesh)
before_faces = len(bm.faces)
before_vertices = len(bm.verts)
bad_before = sum(all(abs(v.co.z - .0675) < .00001 for v in face.verts) and face.normal.z < .9 for face in bm.faces)
# The generator duplicated the vertices for each face before recalculating
# normals. Weld only this road batch so each box is a closed volume; disconnected
# quads have no consistent outside direction for Blender's normal recalculation.
bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=.000001)
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.normal_update()
bad_after = sum(all(abs(v.co.z - .0675) < .00001 for v in face.verts) and face.normal.z < .9 for face in bm.faces)
open_edges = sum(not edge.is_manifold for edge in bm.edges)
assert bad_after == 0 and open_edges == 0 and len(bm.faces) == before_faces, (bad_after, open_edges, len(bm.faces), before_faces)
print("ROAD_NORMALS", "bad_top_faces", bad_before, "->", bad_after, "vertices", before_vertices, "->", len(bm.verts), "faces", len(bm.faces), flush=True)
bm.to_mesh(mesh)
bm.free()
mesh.update()

root = bpy.data.objects["PacificCity"]
bpy.ops.object.select_all(action="DESELECT")
root.select_set(True)
for ob in root.children:
    ob.select_set(True)
temporary = backup / "repaired_city.glb"
bpy.ops.export_scene.gltf(
    filepath=str(temporary), export_format="GLB", use_selection=True,
    use_active_scene=True, export_yup=True, export_cameras=False, export_lights=False,
)
temporary.replace(asset)
bpy.ops.wm.save_as_mainfile(filepath=str(source))
print("CITY_ROAD_REPAIRED", source, asset, flush=True)
