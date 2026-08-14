import bpy

src=bpy.data.objects['Armature']; dst=bpy.data.objects['OBJ-HumanRig (0)']
for f in [1,2,5,10,15,20,25,30,31]:
    bpy.context.scene.frame_set(f)
    print('FRAME',f)
    for n in ['mixamorig:Spine','mixamorig:Spine1','mixamorig:Spine2','mixamorig:Neck','mixamorig:Head']:
        q=src.pose.bones[n].rotation_quaternion.normalized(); print(n,*(round(v,6) for v in q))
    for n in ['CTRL-Spine1','CTRL-Spine2','CTRL-Chest','CTRL-Head']:
        q=dst.pose.bones[n].rotation_quaternion.normalized(); print(n,*(round(v,6) for v in q))
