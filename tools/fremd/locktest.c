#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <sys/wait.h>
static int setlk(int fd,int typ,off_t von,off_t len){
  struct flock fl; memset(&fl,0,sizeof fl);
  fl.l_type=typ; fl.l_whence=SEEK_SET; fl.l_start=von; fl.l_len=len;
  return fcntl(fd,F_SETLK,&fl);
}
int main(void){
  int fd=open("/w/lock.dat",O_RDWR|O_CREAT,0666);
  if(fd<0){printf("lk: open fehl\n");fflush(stdout);return 1;}
  write(fd,"0123456789",10);
  /* 1. eigene Schreibsperre auf 0..9 */
  printf("lk: A setzt WRLCK 0..9 -> %d\n", setlk(fd,F_WRLCK,0,10)); fflush(stdout);
  pid_t p=fork();
  if(p==0){
    /* Kind: EIGENER Prozess, eigene Halterkennung */
    int f2=open("/w/lock.dat",O_RDWR);
    int r1=setlk(f2,F_WRLCK,0,10);      /* muss scheitern */
    printf("lk: B WRLCK 0..9 (belegt) -> %d %s\n", r1, r1<0?"ABGELEHNT-RICHTIG":"GEWAEHRT-FALSCH");
    int r2=setlk(f2,F_WRLCK,100,10);    /* anderer Bereich: frei */
    printf("lk: B WRLCK 100..109 (frei) -> %d %s\n", r2, r2==0?"GEWAEHRT-RICHTIG":"ABGELEHNT-FALSCH");
    /* F_GETLK muss den Halter nennen */
    struct flock fl; memset(&fl,0,sizeof fl);
    fl.l_type=F_WRLCK; fl.l_whence=SEEK_SET; fl.l_start=0; fl.l_len=10;
    int r3=fcntl(f2,F_GETLK,&fl);
    printf("lk: B GETLK 0..9 -> rc=%d typ=%d halter=%d\n", r3, fl.l_type, (int)fl.l_pid);
    fflush(stdout);
    _exit(0);
  }
  int st=0; wait(&st);
  /* 2. freigeben, dann muss es gehen */
  printf("lk: A UNLCK 0..9 -> %d\n", setlk(fd,F_UNLCK,0,10)); fflush(stdout);
  pid_t q=fork();
  if(q==0){
    int f3=open("/w/lock.dat",O_RDWR);
    int r=setlk(f3,F_WRLCK,0,10);
    printf("lk: C WRLCK 0..9 (jetzt frei) -> %d %s\n", r, r==0?"GEWAEHRT-RICHTIG":"ABGELEHNT-FALSCH");
    fflush(stdout); _exit(0);
  }
  wait(&st);
  /* 3. Lesesperren vertragen sich */
  printf("lk: A RDLCK 200..209 -> %d\n", setlk(fd,F_RDLCK,200,10)); fflush(stdout);
  pid_t r2=fork();
  if(r2==0){
    int f4=open("/w/lock.dat",O_RDWR);
    int a=setlk(f4,F_RDLCK,200,10);
    printf("lk: D RDLCK 200..209 (geteilt) -> %d %s\n", a, a==0?"GEWAEHRT-RICHTIG":"ABGELEHNT-FALSCH");
    int b=setlk(f4,F_WRLCK,200,10);
    printf("lk: D WRLCK 200..209 (gegen RDLCK) -> %d %s\n", b, b<0?"ABGELEHNT-RICHTIG":"GEWAEHRT-FALSCH");
    fflush(stdout); _exit(0);
  }
  wait(&st);
  printf("lk: fertig\n"); fflush(stdout);
  return 0;
}
