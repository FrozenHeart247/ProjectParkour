import bpy
o=bpy.data.objects['OBJ-HumanRig (0)'];a=o.animation_data.action;slot=o.animation_data.action_slot
bag=a.layers[0].strips[0].channelbag(slot)
from collections import Counter
c=Counter()
for fc in bag.fcurves:
 for k in fc.keyframe_points:c[k.interpolation]+=1
print(c)
