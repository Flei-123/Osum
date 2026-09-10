/* Wie schnell ist die Firn-erzeugte Grundoperation ueberhaupt?
   Ein Deuter-artiger Kern in C, als OBERGRENZE fuer den Vergleich. */
#include <stdio.h>
#include <stdint.h>
int main(void){
    /* 67 Mio mal: byte lesen, schalten, stapel bewegen */
    static uint64_t stack[8192]; int sp=0;
    static unsigned char code[256]; for(int i=0;i<256;i++) code[i]=(i%5)+32;
    uint64_t n=0;
    for(long k=0;k<67000000;k++){
        unsigned char op=code[k&255];
        switch(op){
        case 32: if(sp<8000) stack[sp++]=k; break;
        case 33: if(sp>0) n+=stack[--sp]; break;
        case 34: n^=k; break;
        case 35: n+=1; break;
        default: n-=1; break;
        }
    }
    printf("%llu %d\n",(unsigned long long)n,sp);
    return 0;
}
