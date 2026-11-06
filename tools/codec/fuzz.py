import random, sys, ref264 as R
random.seed(42)
data=open('/tmp/cm/i_klein.264','rb').read()
n_ok=0; n_exc=0; n_crash=0
arten={}
def run(d, name):
    global n_ok,n_exc,n_crash
    try:
        R.decode_stream(d)
        n_ok+=1
    except (ValueError, IndexError, ZeroDivisionError, KeyError) as e:
        n_exc+=1
        arten[type(e).__name__]=arten.get(type(e).__name__,0)+1
    except RecursionError as e:
        n_crash+=1; print("RECURSION bei",name)
    except Exception as e:
        n_crash+=1
        print("UNERWARTET",type(e).__name__,e,"bei",name)
for k in range(1,30):
    run(data[:len(data)*k//60], "abgeschnitten %d"%k)
for i in range(150):
    b=bytearray(data)
    p=random.randrange(len(b))
    b[p]^=1<<random.randrange(8)
    run(bytes(b), "kipp %d"%i)
for i in range(60):
    b=bytearray(data)
    p=random.randrange(max(1,len(b)-40))
    for k in range(random.randint(1,40)):
        if p+k<len(b): b[p+k]=random.randrange(256)
    run(bytes(b), "muell %d"%i)
for d in [b'', b'\x00\x00\x01', b'\x00\x00\x01\x67', b'\xff'*100,
          b'\x00\x00\x01\x67\xff\xff\xff\xff', b'\x00'*1000]:
    run(d, "sonder")
print("durchgelaufen %d, sauber abgewiesen %d, CRASH %d"%(n_ok,n_exc,n_crash))
print("Ausnahmearten:",arten)
