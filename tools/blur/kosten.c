// DIE FASSUNG, DIE GEBAUT WIRD: zweifacher Kastenfilter, zeilenweise,
// mit EXAKTEM Kehrwert (shift 19, von probe2.c ueber alle n und alle s
// als fehlerfrei nachgewiesen).
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define SHIFT 19
#define RUND  (1u << (SHIFT - 1))
static unsigned *src,*tmp,*dst; static int *sumr,*sumg,*sumb;
static unsigned recip[64];
#define DIV(s,n) ((unsigned)(((unsigned long long)(s) * recip[n] + RUND) >> SHIFT))

static void box_h(unsigned *in, unsigned *out, int w, int h, int r){
    for (int y=0;y<h;y++){
        unsigned *ri=in+(size_t)y*w, *ro=out+(size_t)y*w;
        int sr=0,sg=0,sb=0,n=0;
        for (int x=0;x<=r&&x<w;x++){unsigned p=ri[x];
            sr+=(p>>16)&255; sg+=(p>>8)&255; sb+=p&255; n++;}
        for (int x=0;x<w;x++){
            ro[x]=(DIV(sr,n)<<16)|(DIV(sg,n)<<8)|DIV(sb,n);
            int add=x+r+1, sub=x-r;
            if(add<w){unsigned p=ri[add]; sr+=(p>>16)&255; sg+=(p>>8)&255; sb+=p&255; n++;}
            if(sub>=0){unsigned p=ri[sub]; sr-=(p>>16)&255; sg-=(p>>8)&255; sb-=p&255; n--;}
        }
    }
}
static void box_v_rows(unsigned *in, unsigned *out, int w, int h, int r){
    memset(sumr,0,w*sizeof(int)); memset(sumg,0,w*sizeof(int)); memset(sumb,0,w*sizeof(int));
    int n=0;
    for(int y=0;y<=r&&y<h;y++){unsigned *ri=in+(size_t)y*w;
        for(int x=0;x<w;x++){unsigned p=ri[x]; sumr[x]+=(p>>16)&255; sumg[x]+=(p>>8)&255; sumb[x]+=p&255;} n++;}
    for(int y=0;y<h;y++){
        unsigned *ro=out+(size_t)y*w;
        for(int x=0;x<w;x++)
            ro[x]=(DIV(sumr[x],n)<<16)|(DIV(sumg[x],n)<<8)|DIV(sumb[x],n);
        int add=y+r+1, sub=y-r;
        if(add<h){unsigned *ri=in+(size_t)add*w;
            for(int x=0;x<w;x++){unsigned p=ri[x]; sumr[x]+=(p>>16)&255; sumg[x]+=(p>>8)&255; sumb[x]+=p&255;} n++;}
        if(sub>=0){unsigned *ri=in+(size_t)sub*w;
            for(int x=0;x<w;x++){unsigned p=ri[x]; sumr[x]-=(p>>16)&255; sumg[x]-=(p>>8)&255; sumb[x]-=p&255;} n--;}
    }
}
static double now_ms(void){struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t);
    return t.tv_sec*1000.0+t.tv_nsec/1e6;}

static int probe(void){
    int schlimm=0;
    for(int n=1;n<=33;n++) for(int s=0;s<=n*255;s++){
        int a=(s+n/2)/n, b=(int)DIV(s,n); int d=a-b; if(d<0)d=-d; if(d>schlimm)schlimm=d;}
    return schlimm;
}
static void mess(const char*name,int w,int h,int r){
    size_t n=(size_t)w*h;
    for(size_t i=0;i<n;i++) src[i]=(unsigned)(i*2654435761u);
    int runden=20; double t0=now_ms();
    for(int k=0;k<runden;k++){box_h(src,tmp,w,h,r); box_v_rows(tmp,dst,w,h,r);
        box_h(dst,tmp,w,h,r); box_v_rows(tmp,dst,w,h,r);}
    double ms=(now_ms()-t0)/runden;
    double c0=now_ms();
    for(int k=0;k<runden*20;k++) memcpy(src,dst,n*4);
    double cms=(now_ms()-c0)/(runden*20);
    printf("%-18s %4dx%-5d  blur %7.2f ms  %6.1f%%   kopie %6.3f ms  %5.2f%%  faktor %5.0fx\n",
        name,w,h,ms,100.0*ms/16.7,cms,100.0*cms/16.7,ms/cms);
}
int main(void){
    size_t max=1920*1080;
    src=malloc(max*4); tmp=malloc(max*4); dst=malloc(max*4);
    sumr=malloc(1920*sizeof(int)); sumg=malloc(1920*sizeof(int)); sumb=malloc(1920*sizeof(int));
    for(int n=1;n<64;n++) recip[n]=(unsigned)((((unsigned long long)1<<SHIFT)+n-1)/n);
    printf("PROBE exakter Kehrwert (shift %d) gegen Division: groesster Fehler %d\n\n", SHIFT, probe());
    int r=8;
    printf("zweifacher Kastenfilter, zeilenweise, exakter Kehrwert, Radius %d\n\n",r);
    mess("Benachrichtigung",360,120,r);
    mess("Taskleiste",1920,48,r);
    mess("Startmenue",320,520,r);
    mess("ein Fenster",900,650,r);
    mess("Vollbild FHD",1920,1080,r);
    return 0;
}
/* Gebaut und gelaufen mit:
 *     gcc -O2 -o /tmp/blurkosten tools/blur/kosten.c && /tmp/blurkosten
 * Die Zahlen im Kopf von BEFUND-BLUR.md stammen aus genau diesem Lauf.
 */
