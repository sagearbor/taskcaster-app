#!/usr/bin/env python3
"""Generate assets/ar/bomb.glb — a cartoon bomb that actually reads as a bomb.

Silhouette: matte-black sphere body + gray metal neck + brown fuse cord arcing
up to a bright EMISSIVE spark tip (visible regardless of AR scene lighting).

GLB packing notes (learned the hard way — SceneView/Filament is strict):
- 12-byte header, JSON chunk padded to 4 bytes with SPACES, BIN chunk padded
  with zeros.
- Indices UNSIGNED_SHORT, POSITION accessors must carry min/max.
- The native AR layer treats node scale.x as SceneView `scaleToUnits`, i.e. the
  model's largest dimension gets scaled to that many metres — so absolute
  coordinates here only matter relative to each other.

Run: python3 scripts/gen_ar_bomb.py
"""
import json
import math
import struct
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "assets" / "ar" / "bomb.glb"


def uv_sphere(cx, cy, cz, r, stacks=18, sectors=24):
    verts = []  # (px,py,pz, nx,ny,nz)
    for i in range(stacks + 1):
        phi = math.pi * i / stacks  # 0..pi from +Y pole
        y = math.cos(phi)
        ring = math.sin(phi)
        for j in range(sectors + 1):
            theta = 2.0 * math.pi * j / sectors
            nx, ny, nz = ring * math.cos(theta), y, ring * math.sin(theta)
            verts.append((cx + r * nx, cy + r * ny, cz + r * nz, nx, ny, nz))
    idx = []
    row = sectors + 1
    for i in range(stacks):
        for j in range(sectors):
            a = i * row + j
            b = a + row
            idx += [a, b, a + 1, a + 1, b, b + 1]
    return verts, idx


def cylinder(cx, cz, y0, y1, r, sectors=20):
    verts = []
    idx = []
    for y, _ in ((y0, 0), (y1, 1)):
        for j in range(sectors + 1):
            t = 2.0 * math.pi * j / sectors
            nx, nz = math.cos(t), math.sin(t)
            verts.append((cx + r * nx, y, cz + r * nz, nx, 0.0, nz))
    row = sectors + 1
    for j in range(sectors):
        a, b = j, j + row
        idx += [a, b, a + 1, a + 1, b, b + 1]
    # caps
    for y, ny in ((y0, -1.0), (y1, 1.0)):
        c = len(verts)
        verts.append((cx, y, cz, 0.0, ny, 0.0))
        start = len(verts)
        for j in range(sectors + 1):
            t = 2.0 * math.pi * j / sectors
            verts.append((cx + r * math.cos(t), y, cz + r * math.sin(t), 0.0, ny, 0.0))
        for j in range(sectors):
            if ny > 0:
                idx += [c, start + j, start + j + 1]
            else:
                idx += [c, start + j + 1, start + j]
    return verts, idx


def merge(parts):
    verts, idx = [], []
    for v, i in parts:
        base = len(verts)
        verts += v
        idx += [base + k for k in i]
    return verts, idx


# ---- geometry -------------------------------------------------------------
BODY_R = 0.10
body = uv_sphere(0, 0, 0, BODY_R, stacks=24, sectors=32)
neck = cylinder(0, 0, 0.086, 0.120, 0.034)

# Fuse cord: arc of overlapping beads from neck top curving sideways/up.
fuse_parts = []
N_BEADS = 7
for k in range(N_BEADS):
    t = k / (N_BEADS - 1)
    x = 0.045 * math.sin(t * 1.45)
    y = 0.118 + 0.062 * t
    z = 0.012 * math.sin(t * 2.2)
    fuse_parts.append(uv_sphere(x, y, z, 0.0095, stacks=8, sectors=10))
fuse = merge(fuse_parts)

tip_x = 0.045 * math.sin(1.45)
tip_y = 0.118 + 0.062
tip_z = 0.012 * math.sin(2.2)
spark = uv_sphere(tip_x, tip_y, tip_z, 0.020, stacks=10, sectors=12)

MATERIALS = [
    {  # body — near-black with a hint of blue sheen; faint emissive so it
       # never renders as a pure-black hole against dark scenes.
        "name": "bombBody",
        "pbrMetallicRoughness": {
            "baseColorFactor": [0.05, 0.05, 0.07, 1.0],
            "metallicFactor": 0.85,
            "roughnessFactor": 0.35,
        },
        "emissiveFactor": [0.02, 0.02, 0.03],
    },
    {  # neck — worn gray metal
        "name": "bombNeck",
        "pbrMetallicRoughness": {
            "baseColorFactor": [0.45, 0.45, 0.48, 1.0],
            "metallicFactor": 1.0,
            "roughnessFactor": 0.4,
        },
    },
    {  # fuse cord — tan rope
        "name": "bombFuse",
        "pbrMetallicRoughness": {
            "baseColorFactor": [0.55, 0.42, 0.25, 1.0],
            "metallicFactor": 0.0,
            "roughnessFactor": 0.9,
        },
    },
    {  # spark — hot yellow-orange, fully emissive (ignores scene light)
        "name": "bombSpark",
        "pbrMetallicRoughness": {
            "baseColorFactor": [1.0, 0.8, 0.25, 1.0],
            "metallicFactor": 0.0,
            "roughnessFactor": 0.5,
        },
        "emissiveFactor": [1.0, 0.72, 0.18],
    },
]

PRIMS = [body, neck, fuse, spark]

# ---- pack GLB -------------------------------------------------------------
bin_blob = bytearray()
buffer_views = []
accessors = []
primitives = []


def add_view(data: bytes, target: int) -> int:
    while len(bin_blob) % 4:
        bin_blob.append(0)
    buffer_views.append(
        {"buffer": 0, "byteOffset": len(bin_blob), "byteLength": len(data), "target": target}
    )
    bin_blob.extend(data)
    return len(buffer_views) - 1


for mat_i, (verts, idx) in enumerate(PRIMS):
    pos = b"".join(struct.pack("<3f", v[0], v[1], v[2]) for v in verts)
    nrm = b"".join(struct.pack("<3f", v[3], v[4], v[5]) for v in verts)
    assert len(verts) < 65536, "UNSIGNED_SHORT index overflow"
    ind = b"".join(struct.pack("<H", i) for i in idx)

    xs = [v[0] for v in verts]; ys = [v[1] for v in verts]; zs = [v[2] for v in verts]
    pv = add_view(pos, 34962)
    accessors.append({
        "bufferView": pv, "componentType": 5126, "count": len(verts), "type": "VEC3",
        "min": [min(xs), min(ys), min(zs)], "max": [max(xs), max(ys), max(zs)],
    })
    pos_acc = len(accessors) - 1
    nv = add_view(nrm, 34962)
    accessors.append({"bufferView": nv, "componentType": 5126, "count": len(verts), "type": "VEC3"})
    nrm_acc = len(accessors) - 1
    iv = add_view(ind, 34963)
    accessors.append({"bufferView": iv, "componentType": 5123, "count": len(idx), "type": "SCALAR"})
    idx_acc = len(accessors) - 1

    primitives.append({
        "attributes": {"POSITION": pos_acc, "NORMAL": nrm_acc},
        "indices": idx_acc,
        "material": mat_i,
    })

gltf = {
    "asset": {"version": "2.0", "generator": "taskcaster gen_ar_bomb.py"},
    "scene": 0,
    "scenes": [{"nodes": [0]}],
    "nodes": [{"mesh": 0, "name": "bomb"}],
    "meshes": [{"primitives": primitives, "name": "bomb"}],
    "materials": MATERIALS,
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
with open(OUT, "wb") as f:
    f.write(struct.pack("<3I", 0x46546C67, 2, total))
    f.write(struct.pack("<2I", len(json_bytes), 0x4E4F534A))
    f.write(json_bytes)
    f.write(struct.pack("<2I", len(bin_blob), 0x004E4942))
    f.write(bytes(bin_blob))

print(f"wrote {OUT} ({total} bytes, {sum(len(v) for v, _ in PRIMS)} verts)")
