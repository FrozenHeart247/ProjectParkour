import bpy

s=bpy.data.objects.get('Armature');t=bpy.data.objects.get('OBJ-HumanRig (0)')
a=t.animation_data.action if t and t.animation_data else None
lo=int(a.frame_range[0]);hi=int(a.frame_range[1]);frames=sorted(set([lo,lo+(hi-lo)//4,lo+(hi-lo)//2,lo+3*(hi-lo)//4,hi]))
for f in frames:
 bpy.context.scene.frame_set(f); h=s.pose.bones.get('mixamorig:Hips')
 sw=(s.matrix_world@h.matrix).to_translation()
 print('F',f,'srcworld',tuple(round(x,5) for x in sw))
 for n in ['CTRL-Root','CTRL-TranslationData','CTRL-Pelvis']:
  p=t.pose.bones.get(n); print(n,tuple(round(x,5) for x in p.location),'world',tuple(round(x,5) for x in (t.matrix_world@p.matrix).to_translation()),end=' ')
 for n in ['Bip01','Bip01_Pelvis']:
  p=t.pose.bones.get(n)
  if p: print(n,'world',tuple(round(x,5) for x in (t.matrix_world@p.matrix).to_translation()),end=' ')
 print()
