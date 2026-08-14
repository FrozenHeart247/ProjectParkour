import bpy, math

s=bpy.data.objects['Armature']; t=bpy.data.objects['OBJ-HumanRig (0)']
maps={
 'mixamorig:Hips':'CTRL-Pelvis','mixamorig:Spine':'CTRL-Spine1','mixamorig:Head':'CTRL-Head',
 'mixamorig:LeftArm':'CTRL-UpperArmFK.L','mixamorig:LeftForeArm':'CTRL-ForearmFK.L','mixamorig:LeftHand':'CTRL-HandFK.L',
 'mixamorig:LeftUpLeg':'CTRL-ThighFK.L','mixamorig:LeftLeg':'CTRL-CalfFK.L','mixamorig:LeftFoot':'CTRL-FootFK.L'}
for f in [1,10,20,31]:
 bpy.context.scene.frame_set(f); print('F',f)
 for sn,tn in maps.items():
  sp=s.pose.bones[sn]; tp=t.pose.bones[tn]; sr=s.data.bones[sn]
  swp=s.matrix_world@sp.matrix; swr=s.matrix_world@sr.matrix_local; twr=t.matrix_world@tp.bone.matrix_local
  desired_local=t.matrix_world.inverted()@(swp@swr.inverted()@twr)
  saved=tp.matrix_basis.copy(); tp.matrix=desired_local; bpy.context.view_layer.update()
  q1=tp.rotation_quaternion.copy().normalized(); tp.matrix_basis=saved; bpy.context.view_layer.update(); q2=tp.rotation_quaternion.copy().normalized()
  e=math.degrees(q1.rotation_difference(q2).angle);e=min(e,abs(360-e))
  print(sn,tn,'err basis',e)
