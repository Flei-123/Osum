import re,sys,collections,json
HDR=re.compile(r"(export\s+)?fn\s+([A-Za-z0-9_]+)\s*\(([^)]*)\)\s*(?:->\s*([A-Za-z0-9_*\s]+?))?\s*\{")
def blocks(text):
    for m in HDR.finditer(text):
        i=m.end()-1; d=0; j=i
        while j<len(text):
            if text[j]=='{': d+=1
            elif text[j]=='}':
                d-=1
                if d==0: break
            j+=1
        yield m,text[m.start():j+1],text[m.end():j]
def norm(m,body):
    params=[p.strip() for p in m.group(3).split(',') if p.strip()]
    names=[p.split(':')[0].strip() for p in params]
    types=[p.split(':',1)[1].strip() for p in params]
    b=body
    for k,n in enumerate(names):
        b=re.sub(r'\b%s\b'%re.escape(n),'@%d'%k,b)
    b=re.sub(r'\s+',' ',b).strip()
    return '(%s)->%s {%s}'%(','.join(types),(m.group(4) or '').strip(),b)
def scan(files):
    out=collections.defaultdict(lambda: collections.defaultdict(list))
    for f in files:
        t=open(f,errors='replace').read()
        t=re.sub(r'//[^\n]*','',t)
        for m,full,body in blocks(t):
            out[m.group(2)][norm(m,body)].append(f)
    return out
if __name__=='__main__':
    import subprocess
    files=subprocess.check_output(['git','ls-files','*.fi']).decode().split()
    files=[f for f in files if not f.startswith('vendor/') and not f.startswith('tests/')]
    r=scan(files)
    names=sys.argv[1:]
    for n in names:
        for form,fs in sorted(r.get(n,{}).items(),key=lambda x:-len(x[1])):
            print(n,len(fs),form[:200])
