import bpy, math
s=bpy.data.objects['Armature'];t=bpy.data.objects['OBJ-HumanRig (0)']
def e(a,b):
 x=math.degrees(a.rotation_difference(b).angle);return min(x,abs(360-x))
for f in [1,5,10,15,20,25,31]:
 bpy.context.scene.frame_set(f)
 q1=s.pose.bones['mixamorig:Spine1'].rotation_quaternion.normalized();q2=s.pose.bones['mixamorig:Spine2'].rotation_quaternion.normalized();qt=t.pose.bones['CTRL-Spine2'].rotation_quaternion.normalized()
 tr=(t.matrix_world@t.data.bones['CTRL-Spine2'].matrix_local).to_quaternion(); sr=(s.matrix_world@s.data.bones['mixamorig:Spine1'].matrix_local).to_quaternion();c=tr.inverted()@sr
 qa=c@(q1@q2)@c.inverted();qb=c@(q2@q1)@c.inverted();print(f,e(qa,qt),e(qb,qt))
