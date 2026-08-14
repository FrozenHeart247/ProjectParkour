import bpy
import json
import math
from mathutils import Matrix, Quaternion, Vector


src = bpy.data.objects.get("Armature")
dst = bpy.data.objects.get("OBJ-HumanRig (0)")

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


def qerr(a, b):
    return math.degrees(a.rotation_difference(b).angle)


def matrot(m):
    return m.to_quaternion().normalized()


out = {"file": bpy.data.filepath, "frames": {}}
for frame in [1, 2, 5, 10, 15, 20, 25, 30, 31]:
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()
    fr = {}
    for sn, tn in mapping.items():
        s = src.pose.bones.get(sn)
        t = dst.pose.bones.get(tn)
        if not s or not t:
            continue
        sr = s.bone.matrix_local
        tr = t.bone.matrix_local
        sp = s.matrix.copy()
        tp = t.matrix.copy()

        # Candidate A: global pose-rest delta applied on left.
        ca = sp @ sr.inverted() @ tr
        # Candidate B: target rest times source local pose delta.
        cb = tr @ sr.inverted() @ sp
        # Candidate C: conjugated global delta.
        delta = sp @ sr.inverted()
        cc = tr @ delta
        # Candidate D: transfer local channel rotation (matrix_basis rotation).
        cd = tr @ s.matrix_basis
        fr[sn + " -> " + tn] = {
            "err_A": qerr(matrot(ca), matrot(tp)),
            "err_B": qerr(matrot(cb), matrot(tp)),
            "err_D": qerr(matrot(cd), matrot(tp)),
            "src_basis_q": list(s.matrix_basis.to_quaternion()),
            "target_basis_q": list(t.matrix_basis.to_quaternion()),
            "target_rotmode": t.rotation_mode,
        }
    out["frames"][str(frame)] = fr

for obj in (src, dst):
    out[obj.name + "_world"] = [list(row) for row in obj.matrix_world]
    out[obj.name + "_scale"] = list(obj.scale)

for frame in [1, 10, 20, 31]:
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()
    for name in ["CTRL-Root", "CTRL-TranslationData", "CTRL-Pelvis"]:
        p = dst.pose.bones.get(name)
        out.setdefault("target_controls", {}).setdefault(str(frame), {})[name] = {
            "loc": list(p.location),
            "basis_loc": list(p.matrix_basis.to_translation()),
            "pose_loc": list(p.matrix.to_translation()),
            "rot_q": list(p.rotation_quaternion),
        }
    h = src.pose.bones["mixamorig:Hips"]
    out.setdefault("src_hips", {})[str(frame)] = {
        "loc": list(h.location),
        "basis_loc": list(h.matrix_basis.to_translation()),
        "pose_loc": list(h.matrix.to_translation()),
        "world_head": list((src.matrix_world @ h.matrix).to_translation()),
    }

print("RETARGET_COMPARE_BEGIN")
print(json.dumps(out, indent=2))
print("RETARGET_COMPARE_END")
