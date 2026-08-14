import bpy

print('FILE',bpy.data.filepath)
for obj in bpy.data.objects:
    if obj.type!='ARMATURE':continue
    a=obj.animation_data.action if obj.animation_data else None
    print('ARM',obj.name,'act',a.name if a else None,'range',tuple(a.frame_range) if a else None,'worldscale',tuple(obj.matrix_world.to_scale()))
    if obj.name.startswith('OBJ-HumanRig') and a:
        lo=int(a.frame_range[0]);hi=int(a.frame_range[1]);frames=sorted(set([lo,lo+(hi-lo)//4,lo+(hi-lo)//2,lo+3*(hi-lo)//4,hi]))
        for f in frames:
            bpy.context.scene.frame_set(f)
            print('F',f,end=' ')
            for n in ['CTRL-Root','CTRL-TranslationData','CTRL-Pelvis']:
                p=obj.pose.bones.get(n)
                if p:print(n,'loc',tuple(round(x,5) for x in p.location),end='; ')
            print()
