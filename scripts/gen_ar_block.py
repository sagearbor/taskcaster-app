#!/usr/bin/env python3
"""Generate assets/ar/block_*.glb — the Tower Trials stacking cubes.

One shared cube mesh (per-face normals so the faces shade distinctly) written
six times with different materials:
  block_base.glb    warm wood-brown anchor block (round start)
  block_red.glb     player colors …
  block_blue.glb
  block_green.glb
  block_yellow.glb
  block_ghost.glb   translucent white preview block (alphaMode BLEND)

GLB packing notes (same hard-won rules as gen_ar_bomb.py — SceneView/Filament
is strict):
- 12-byte header, JSON chunk padded to 4 bytes with SPACES, BIN chunk padded
  with zeros.
- Indices UNSIGNED_SHORT, POSITION accessors must carry min/max.
- The native AR layer treats node scale.x as SceneView `scaleToUnits`: the
  model's largest dimension is normalized to that many metres, so the absolute
  size here (0.24 m) only matters relative to itself. The engine spawns at
  scaleToUnits 0.25 → every block renders as a ~25 cm cube, which is what
  TowerTrialsController.blockSize assumes.

Run: python3 scripts/gen_ar_block.py
"""
import json
import struct
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "ar"

HALF = 0.12  # native half-edge → 0.24 m cube before scaleToUnits


def cube(half):
    """24-vertex cube (4 verts per face, per-face normals) centred on origin."""
    verts = []  # (px,py,pz, nx,ny,nz)
    idx = []
    # (normal, u axis, v axis) with u × v = normal so winding is CCW from
    # outside (front-facing for glTF's default counter-clockwise convention).
    faces = [
        ((0, 0, 1), (1, 0, 0), (0, 1, 0)),
        ((0, 0, -1), (-1, 0, 0), (0, 1, 0)),
        ((1, 0, 0), (0, 0, -1), (0, 1, 0)),
        ((-1, 0, 0), (0, 0, 1), (0, 1, 0)),
        ((0, 1, 0), (1, 0, 0), (0, 0, -1)),
        ((0, -1, 0), (1, 0, 0), (0, 0, 1)),
    ]
    for n, u, v in faces:
        base = len(verts)
        for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            p = [(n[k] + su * u[k] + sv * v[k]) * half for k in range(3)]
            verts.append((p[0], p[1], p[2], float(n[0]), float(n[1]), float(n[2])))
        idx += [base, base + 1, base + 2, base, base + 2, base + 3]
    return verts, idx


# name -> (rgb, alpha). A faint emissive floor keeps blocks readable in dark
# rooms (same trick as the bomb body); the ghost is brighter + blended.
BLOCKS = {
    "block_base": ((0.55, 0.42, 0.28), 1.0),
    "block_red": ((0.85, 0.20, 0.17), 1.0),
    "block_blue": ((0.16, 0.44, 0.86), 1.0),
    "block_green": ((0.21, 0.64, 0.30), 1.0),
    "block_yellow": ((0.95, 0.75, 0.14), 1.0),
    "block_ghost": ((0.88, 0.94, 1.00), 0.35),
}


def material(name, rgb, alpha):
    mat = {
        "name": name,
        "pbrMetallicRoughness": {
            "baseColorFactor": [rgb[0], rgb[1], rgb[2], alpha],
            "metallicFactor": 0.0,
            "roughnessFactor": 0.55,
        },
        "emissiveFactor": [rgb[0] * 0.06, rgb[1] * 0.06, rgb[2] * 0.06],
    }
    if alpha < 1.0:
        mat["alphaMode"] = "BLEND"
        mat["doubleSided"] = True
        # A ghost must glow a little of its own accord or it vanishes at dusk.
        mat["emissiveFactor"] = [rgb[0] * 0.25, rgb[1] * 0.25, rgb[2] * 0.25]
    return mat


def write_glb(path, verts, idx, mat):
    bin_blob = bytearray()
    buffer_views = []
    accessors = []

    def add_view(data, target):
        while len(bin_blob) % 4:
            bin_blob.append(0)
        buffer_views.append({
            "buffer": 0,
            "byteOffset": len(bin_blob),
            "byteLength": len(data),
            "target": target,
        })
        bin_blob.extend(data)
        return len(buffer_views) - 1

    pos = b"".join(struct.pack("<3f", v[0], v[1], v[2]) for v in verts)
    nrm = b"".join(struct.pack("<3f", v[3], v[4], v[5]) for v in verts)
    assert len(verts) < 65536, "UNSIGNED_SHORT index overflow"
    ind = b"".join(struct.pack("<H", i) for i in idx)

    xs = [v[0] for v in verts]
    ys = [v[1] for v in verts]
    zs = [v[2] for v in verts]
    pv = add_view(pos, 34962)
    accessors.append({
        "bufferView": pv, "componentType": 5126, "count": len(verts),
        "type": "VEC3",
        "min": [min(xs), min(ys), min(zs)],
        "max": [max(xs), max(ys), max(zs)],
    })
    nv = add_view(nrm, 34962)
    accessors.append({
        "bufferView": nv, "componentType": 5126, "count": len(verts),
        "type": "VEC3",
    })
    iv = add_view(ind, 34963)
    accessors.append({
        "bufferView": iv, "componentType": 5123, "count": len(idx),
        "type": "SCALAR",
    })

    gltf = {
        "asset": {"version": "2.0", "generator": "taskcaster gen_ar_block.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": "block"}],
        "meshes": [{
            "primitives": [{
                "attributes": {"POSITION": 0, "NORMAL": 1},
                "indices": 2,
                "material": 0,
            }],
            "name": "block",
        }],
        "materials": [mat],
        "buffers": [{"byteLength": len(bin_blob)}],
        "bufferViews": buffer_views,
        "accessors": accessors,
    }

    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(json_bytes) % 4:
        json_bytes += b" "
    while len(bin_blob) % 4:
        bin_blob.append(0)

    total = 12 + 8 + len(json_bytes) + 8 + len(bin_blob)
    with open(path, "wb") as f:
        f.write(struct.pack("<3I", 0x46546C67, 2, total))
        f.write(struct.pack("<2I", len(json_bytes), 0x4E4F534A))
        f.write(json_bytes)
        f.write(struct.pack("<2I", len(bin_blob), 0x004E4942))
        f.write(bytes(bin_blob))
    print(f"wrote {path} ({total} bytes)")


def main():
    verts, idx = cube(HALF)
    for name, (rgb, alpha) in BLOCKS.items():
        write_glb(OUT_DIR / f"{name}.glb", verts, idx, material(name, rgb, alpha))


if __name__ == "__main__":
    main()
