#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <sys/syscall.h>
/* brk direkt per Syscall, an musls malloc vorbei. */
static void* rawbrk(void*p){ return (void*)syscall(SYS_brk,p); }
static void pruef(const char*wo){
  unsigned char *cur = (unsigned char*)rawbrk(0);
  unsigned char *neu = (unsigned char*)rawbrk(cur+8192);
  if (neu != cur+8192){ printf("bz2: %s brk verweigert cur=%p neu=%p\n",wo,cur,neu); fflush(stdout); return; }
  int nz=0; unsigned char first=0; int firsti=-1;
  for (int i=0;i<8192;i++){ if(cur[i]){ if(!nz){first=cur[i];firsti=i;} nz++; } }
  printf("bz2: %s frische-brk-seiten nichtnull=%d von 8192 erstes=0x%02x@%d\n", wo, nz, first, firsti);
  fflush(stdout);
}
int main(int argc, char**argv){
  if (argc>1 && !strcmp(argv[1],"k")) { pruef("nach-execve"); return 0; }
  pruef("frisch");
  char *av[3]; av[0]=argv[0]; av[1]="k"; av[2]=0;
  execve(argv[0],av,0);
  return 1;
}
