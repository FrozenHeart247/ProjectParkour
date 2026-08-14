import bpy, math
s=bpy.data.objects['Armature'];t=bpy.data.objects['OBJ-HumanRig (0)']
def err(a,b):
 x=math.degrees(a.rotation_difference(b).angle);return min(x,abs(360-x))
def C(sn,tn):return (t.matrix_world@t.data.bones[tn].matrix_local).to_quaternion().inverted()@(s.matrix_world@s.data.bones[sn].matrix_local).to_quaternion()
c1=C('mixamorig:Spine1','CTRL-Spine2');c2=C('mixamorig:Spine2','CTRL-Spine2')
for f in [1,5,10,15,20,25,31]:
 bpy.context.scene.frame_set(f);a=s.pose.bones['mixamorig:Spine1'].rotation_quaternion.normalized();b=s.pose.bones['mixamorig:Spine2'].rotation_quaternion.normalized();ta=c1@a@c1.inverted();tb=c2@b@c2.inverted();q=t.pose.bones['CTRL-Spine2'].rotation_quaternion.normalized()
 print(f,'ta*tb',err(ta@tb,q),'tb*ta',err(tb@ta,q),'c1(a*b)',err(c1@(a@b)@c1.inverted(),q),'c2(a*b)',err(c2@(a@b)@c2.inverted(),q))
