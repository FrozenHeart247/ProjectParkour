import bpy, math
s=bpy.data.objects['Armature'];t=bpy.data.objects['OBJ-HumanRig (0)']
maps=[
('mixamorig:Hips','CTRL-Pelvis'),('mixamorig:Spine','CTRL-Spine1'),
('mixamorig:Spine1','CTRL-Spine2'),('mixamorig:Neck','CTRL-Chest'),('mixamorig:Head','CTRL-Head'),
('mixamorig:LeftShoulder','CTRL-Shoulder.L'),('mixamorig:RightShoulder','CTRL-Shoulder.R'),
('mixamorig:LeftArm','CTRL-UpperArmFK.L'),('mixamorig:RightArm','CTRL-UpperArmFK.R'),
('mixamorig:LeftForeArm','CTRL-ForearmFK.L'),('mixamorig:RightForeArm','CTRL-ForearmFK.R'),
('mixamorig:LeftHand','CTRL-HandFK.L'),('mixamorig:RightHand','CTRL-HandFK.R'),
('mixamorig:LeftUpLeg','CTRL-ThighFK.L'),('mixamorig:RightUpLeg','CTRL-ThighFK.R'),
('mixamorig:LeftLeg','CTRL-CalfFK.L'),('mixamorig:RightLeg','CTRL-CalfFK.R'),
('mixamorig:LeftFoot','CTRL-FootFK.L'),('mixamorig:RightFoot','CTRL-FootFK.R')]

def qerr(a,b):
 e=math.degrees(a.rotation_difference(b).angle);return min(e,abs(360-e))
for f in [1,10,20,31]:
 bpy.context.scene.frame_set(f);bpy.context.view_layer.update();saved={tn:t.pose.bones[tn].matrix_basis.copy() for _,tn in maps}
 for sn,tn in maps:
  sp=s.pose.bones[sn];tp=t.pose.bones[tn]
  d=t.matrix_world.inverted()@((s.matrix_world@sp.matrix)@(s.matrix_world@s.data.bones[sn].matrix_local).inverted()@(t.matrix_world@tp.bone.matrix_local))
  tp.matrix=d;bpy.context.view_layer.update()
 print('F',f)
 for sn,tn in maps:print(tn,round(qerr(t.pose.bones[tn].rotation_quaternion.normalized(),saved[tn].to_quaternion().normalized()),5))
 for _,tn in reversed(maps):t.pose.bones[tn].matrix_basis=saved[tn]
 bpy.context.view_layer.update()
