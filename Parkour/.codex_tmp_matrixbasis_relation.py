import bpy, math
s=bpy.data.objects['Armature'];t=bpy.data.objects['OBJ-HumanRig (0)']
maps=[('mixamorig:Hips','CTRL-Pelvis'),('mixamorig:Spine','CTRL-Spine1'),('mixamorig:Spine1','CTRL-Spine2'),('mixamorig:Neck','CTRL-Chest'),('mixamorig:Head','CTRL-Head'),('mixamorig:LeftShoulder','CTRL-Shoulder.L'),('mixamorig:LeftArm','CTRL-UpperArmFK.L'),('mixamorig:LeftForeArm','CTRL-ForearmFK.L'),('mixamorig:LeftHand','CTRL-HandFK.L'),('mixamorig:LeftUpLeg','CTRL-ThighFK.L'),('mixamorig:LeftLeg','CTRL-CalfFK.L'),('mixamorig:LeftFoot','CTRL-FootFK.L')]
def e(a,b):
 x=math.degrees(a.rotation_difference(b).angle);return min(x,abs(360-x))
for sn,tn in maps:
 errs=[]
 for f in [1,5,10,15,20,25,31]:
  bpy.context.scene.frame_set(f)
  sp=s.pose.bones[sn];tp=t.pose.bones[tn]
  swp=s.matrix_world@sp.matrix;swr=s.matrix_world@s.data.bones[sn].matrix_local;twr=t.matrix_world@tp.bone.matrix_local
  d=t.matrix_world.inverted()@(swp@swr.inverted()@twr)
  # Solve raw local basis from desired armature-space matrix without constraints.
  if tp.parent:
   parent_pose=tp.parent.matrix
   parent_rest=tp.parent.bone.matrix_local
   rest=tp.bone.matrix_local
   basis=(parent_pose@parent_rest.inverted()@rest).inverted()@d
  else:
   basis=tp.bone.matrix_local.inverted()@d
  errs.append(e(basis.to_quaternion(),tp.matrix_basis.to_quaternion()))
 print(sn,tn,'mean',sum(errs)/len(errs),'max',max(errs),[round(x,3) for x in errs])
