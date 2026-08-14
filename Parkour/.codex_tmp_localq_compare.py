import bpy, math
s=bpy.data.objects['Armature'];t=bpy.data.objects['OBJ-HumanRig (0)']
maps=[('mixamorig:Hips','CTRL-Pelvis'),('mixamorig:Spine','CTRL-Spine1'),('mixamorig:Spine1','CTRL-Spine2'),('mixamorig:Spine2','CTRL-Spine2'),('mixamorig:Neck','CTRL-Chest'),('mixamorig:Head','CTRL-Head'),('mixamorig:LeftShoulder','CTRL-Shoulder.L'),('mixamorig:LeftArm','CTRL-UpperArmFK.L'),('mixamorig:LeftForeArm','CTRL-ForearmFK.L'),('mixamorig:LeftHand','CTRL-HandFK.L'),('mixamorig:LeftUpLeg','CTRL-ThighFK.L'),('mixamorig:LeftLeg','CTRL-CalfFK.L'),('mixamorig:LeftFoot','CTRL-FootFK.L')]
def e(a,b):
 x=math.degrees(a.rotation_difference(b).angle);return min(x,abs(360-x))
for sn,tn in maps:
 es=[]
 for f in [1,5,10,15,20,25,31]:
  bpy.context.scene.frame_set(f)
  qs=s.pose.bones[sn].rotation_quaternion.normalized();qt=t.pose.bones[tn].rotation_quaternion.normalized()
  # derive axis map C from world rest rotations object-space
  sr=(s.matrix_world@s.data.bones[sn].matrix_local).to_quaternion();tr=(t.matrix_world@t.data.bones[tn].matrix_local).to_quaternion();c=tr.inverted() # dummy
  # use signed-permutation direct by calculate c from rest bone local rotations? Try C=tr^-1*object world rot*sr
  c=tr.inverted()@s.matrix_world.to_quaternion()@sr # no
  # Expected observed is conjugation with C from fit, which can be derived rest coordinate frames:
  C=(t.matrix_world@t.data.bones[tn].matrix_local).to_quaternion().inverted()@(s.matrix_world@s.data.bones[sn].matrix_local).to_quaternion()
  for formula in [C@qs@C.inverted(),C.inverted()@qs@C]: pass
  es.append((e(C@qs@C.inverted(),qt),e(C.inverted()@qs@C,qt)))
 print(sn,tn,'A',sum(x[0] for x in es)/len(es),max(x[0] for x in es),'B',sum(x[1] for x in es)/len(es),max(x[1] for x in es))
