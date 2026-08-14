import bpy
s=bpy.data.objects['Armature'];t=bpy.data.objects['OBJ-HumanRig (0)'];a=t.animation_data.action;lo=int(a.frame_range[0]);hi=int(a.frame_range[1])
bpy.context.scene.frame_set(lo); p0=(s.matrix_world@s.pose.bones['mixamorig:Hips'].matrix).to_translation(); td0=t.pose.bones['CTRL-TranslationData'].location.copy();r0=t.pose.bones['CTRL-Root'].location.copy()
for f in [lo+(hi-lo)//4,lo+(hi-lo)//2,lo+3*(hi-lo)//4,hi]:
 bpy.context.scene.frame_set(f);p=(s.matrix_world@s.pose.bones['mixamorig:Hips'].matrix).to_translation();d=p-p0;td=t.pose.bones['CTRL-TranslationData'].location-td0;r=t.pose.bones['CTRL-Root'].location-r0
 print(f,'srcdelta',tuple(d),'TD',tuple(td),'R',tuple(r))
