import sys, ref264
ref264.Dec.decode_slice = ref264.Dec.decode_slice
name=sys.argv[1]
data=open('/tmp/cm/%s.264'%name,'rb').read()
d,frames=ref264.decode_stream(data)
print(name,"Bilder:",len(frames), frames[0].w if frames else 0, frames[0].h if frames else 0)
ref264.dump_yuv(frames,'/tmp/out_%s.yuv'%name)
ref=open('/tmp/cm/%s.yuv'%name,'rb').read()
mine=open('/tmp/out_%s.yuv'%name,'rb').read()
print(" Groesse soll",len(ref),"ist",len(mine))
n=min(len(ref),len(mine))
diff=sum(1 for i in range(n) if ref[i]!=mine[i])
mx=max((abs(ref[i]-mine[i]) for i in range(n)), default=0)
print(" abweichende Oktette:",diff,"von",n," maxdiff",mx)
