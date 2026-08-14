import bpy, numpy as np, math, json
from mathutils import Matrix

s=bpy.data.objects['Armature']; t=bpy.data.objects['OBJ-HumanRig (0)']

def fit(label, get_s, tname):
    xs=[]; ys=[]; pairs=[]
    for f in range(1,32):
        bpy.context.scene.frame_set(f)
        qs=get_s().normalized(); qt=t.pose.bones[tname].rotation_quaternion.copy().normalized()
        if qs.w*qt.w<0: qt.negate()
        xs.append([qs.x,qs.y,qs.z]); ys.append([qt.x,qt.y,qt.z]); pairs.append((qs,qt))
    X=np.asarray(xs).T;Y=np.asarray(ys).T
    U,_,Vt=np.linalg.svd(Y@X.T);R=U@Vt
    if np.linalg.det(R)<0:U[:,-1]*=-1;R=U@Vt
    c=Matrix(R.tolist()).to_quaternion().normalized(); errs=[];werr=[]
    for qs,qt in pairs:
        qp=c@qs@c.conjugated();errs.append(math.degrees(qp.rotation_difference(qt).angle));werr.append(abs(qs.w-qt.w))
    print(label,'C',*(round(x,12) for x in [c.w,c.x,c.y,c.z]),'mean',sum(errs)/len(errs),'max',max(errs),'w',max(werr))

fit('Spine1','') if False else None
fit('Spine1 target',lambda:s.pose.bones['mixamorig:Spine'].rotation_quaternion.copy(),'CTRL-Spine1')
fit('Spine12 product q1q2',lambda:s.pose.bones['mixamorig:Spine1'].rotation_quaternion.copy()@s.pose.bones['mixamorig:Spine2'].rotation_quaternion.copy(),'CTRL-Spine2')
fit('Spine12 product q2q1',lambda:s.pose.bones['mixamorig:Spine2'].rotation_quaternion.copy()@s.pose.bones['mixamorig:Spine1'].rotation_quaternion.copy(),'CTRL-Spine2')
fit('Chest Neck',lambda:s.pose.bones['mixamorig:Neck'].rotation_quaternion.copy(),'CTRL-Chest')
