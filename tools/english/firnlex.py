"""Minimal Firn lexer: split a .fi line-set into CODE vs STRING/CHAR/COMMENT regions.
Renaming is only ever applied to CODE regions."""
import re

def spans(text):
    """Yield (kind, start, end) over the whole text. kind in code/str/chr/cmt."""
    i=0; n=len(text); out=[]; cur=0
    while i<n:
        c=text[i]
        if c=='"':
            if cur<i: out.append(('code',cur,i))
            j=i+1
            while j<n:
                if text[j]=='\\': j+=2; continue
                if text[j]=='"': j+=1; break
                if text[j]=='\n': break
                j+=1
            out.append(('str',i,j)); i=j; cur=i; continue
        if c=="'":
            if cur<i: out.append(('code',cur,i))
            j=i+1
            while j<n:
                if text[j]=='\\': j+=2; continue
                if text[j]=="'": j+=1; break
                if text[j]=='\n': break
                j+=1
            out.append(('chr',i,j)); i=j; cur=i; continue
        if c=='/' and i+1<n and text[i+1]=='/':
            if cur<i: out.append(('code',cur,i))
            j=text.find('\n',i)
            j=n if j<0 else j
            out.append(('cmt',i,j)); i=j; cur=i; continue
        if c=='/' and i+1<n and text[i+1]=='*':
            if cur<i: out.append(('code',cur,i))
            j=text.find('*/',i+2)
            j=n if j<0 else j+2
            out.append(('cmt',i,j)); i=j; cur=i; continue
        i+=1
    if cur<n: out.append(('code',cur,n))
    return out

def rename_code_only(text, mapping):
    """Replace whole-word identifiers from mapping ONLY in code regions."""
    if not mapping: return text, 0
    pat=re.compile(r'\b(' + '|'.join(sorted(map(re.escape,mapping),key=len,reverse=True)) + r')\b')
    parts=[]; cnt=0
    for kind,a,b in spans(text):
        seg=text[a:b]
        if kind=='code':
            seg,k=pat.subn(lambda m: mapping[m.group(1)], seg); cnt+=k
        parts.append(seg)
    return ''.join(parts), cnt
