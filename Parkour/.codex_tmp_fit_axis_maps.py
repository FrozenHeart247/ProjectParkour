import bpy
import json
import math
import numpy as np
from mathutils import Matrix, Quaternion

src = bpy.data.objects["Armature"]
dst = bpy.data.objects["OBJ-HumanRig (0)"]

mapping = {
    "mixamorig:Hips": "CTRL-Pelvis",
    "mixamorig:Spine": "CTRL-Spine1",
    "mixamorig:Spine1": "CTRL-Spine2",
    "mixamorig:Spine2": "CTRL-Chest",
    "mixamorig:Head": "CTRL-Head",
    "mixamorig:LeftShoulder": "CTRL-Shoulder.L",
    "mixamorig:LeftArm": "CTRL-UpperArmFK.L",
    "mixamorig:LeftForeArm": "CTRL-ForearmFK.L",
    "mixamorig:LeftHand": "CTRL-HandFK.L",
    "mixamorig:RightShoulder": "CTRL-Shoulder.R",
    "mixamorig:RightArm": "CTRL-UpperArmFK.R",
    "mixamorig:RightForeArm": "CTRL-ForearmFK.R",
    "mixamorig:RightHand": "CTRL-HandFK.R",
    "mixamorig:LeftUpLeg": "CTRL-ThighFK.L",
    "mixamorig:LeftLeg": "CTRL-CalfFK.L",
    "mixamorig:LeftFoot": "CTRL-FootFK.L",
    "mixamorig:RightUpLeg": "CTRL-ThighFK.R",
    "mixamorig:RightLeg": "CTRL-CalfFK.R",
    "mixamorig:RightFoot": "CTRL-FootFK.R",
}

out = {}
for sn, tn in mapping.items():
    xs, ys = [], []
    samples = []
    for frame in range(1, 32):
        bpy.context.scene.frame_set(frame)
        qs = src.pose.bones[sn].rotation_quaternion.copy().normalized()
        qt = dst.pose.bones[tn].rotation_quaternion.copy().normalized()
        if qs.w * qt.w < 0:
            qt.negate()
        xs.append([qs.x, qs.y, qs.z])
        ys.append([qt.x, qt.y, qt.z])
        samples.append((qs, qt))
    X = np.asarray(xs).T
    Y = np.asarray(ys).T
    U, S, Vt = np.linalg.svd(Y @ X.T)
    R = U @ Vt
    if np.linalg.det(R) < 0:
        U[:, -1] *= -1
        R = U @ Vt
    qC = Matrix(R.tolist()).to_quaternion().normalized()
    errs = []
    werrs = []
    for qs, qt in samples:
        pred = qC @ qs @ qC.conjugated()
        errs.append(math.degrees(pred.rotation_difference(qt).angle))
        werrs.append(abs(qs.w - qt.w))
    out[sn + " -> " + tn] = {
        "axis_q_wxyz": [qC.w, qC.x, qC.y, qC.z],
        "axis_matrix": R.tolist(),
        "max_deg": max(errs),
        "mean_deg": sum(errs) / len(errs),
        "max_werr": max(werrs),
        "det": float(np.linalg.det(R)),
    }

print("AXIS_MAP_BEGIN")
print(json.dumps(out, indent=2))
print("AXIS_MAP_END")
