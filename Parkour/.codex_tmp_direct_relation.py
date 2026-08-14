import bpy,math
s=bpy.data.objects['Armature'];t=bpy.data.objects['OBJ-HumanRig (0)']
maps=[('mixamorig:Hips','CTRL-Pelvis'),('mixamorig:Spine','CTRL-Spine1'),('mixamorig:Neck','CTRL-Chest'),('mixamorig:Head','CTRL-Head'),('mixamorig:LeftShoulder','CTRL-Shoulder.L'),('mixamorig:LeftArm','CTRL-UpperArmFK.L'),('mixamorig:LeftForeArm','CTRL-ForearmFK.L'),('mixamorig:LeftHand','CTRL-HandFK.L'),('mixamorig:LeftUpLeg','CTRL-ThighFK.L'),('mixamorig:LeftLeg','CTRL-CalfFK.L'),('mixamorig:LeftFoot','CTRL-FootFK.L')]
def e(a,b):
 x=math.degrees(a.rotation_difference(b).angle);return min(x,abs(360-x))
for sn,tn in maps:
 es=[]
 for f in [1,5,10,15,20,25,31]:
  bpy.context.scene.frame_set(f);qs=s.pose.bones[sn].rotation_quaternion.normalized();qt=t.pose.bones[tn].rotation_quaternion.normalized();sr=(s.matrix_world@s.data.bones[sn].matrix_local).to_quaternion();tr=(t.matrix_world@t.data.bones[tn].matrix_local).to_quaternion();C=tr.inverted()@sr;es.append(e(C@qs@C.inverted(),qt))
 print(sn,tn,sum(es)/len(es),max(es))
