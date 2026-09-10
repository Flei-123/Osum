#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <string.h>
int main(void){
  printf("fork: start\n"); fflush(stdout);
  /* Halde VOR dem fork anfassen */
  char *a = malloc(100); strcpy(a,"vater");
  pid_t p = fork();
  if (p == 0) {
    /* Kind: eigene Halde benutzen */
    char *b = malloc(200); strcpy(b,"kind");
    printf("fork: kind sieht [%s], eigenes [%s]\n", a, b);
    fflush(stdout);
    _exit(7);
  }
  if (p < 0) { printf("fork: FEHLER %d\n", (int)p); fflush(stdout); return 1; }
  int st=0; pid_t w = wait(&st);
  printf("fork: vater pid=%d kind=%d gewartet=%d status=%d exited=%d code=%d\n",
     (int)getpid(), (int)p, (int)w, st, WIFEXITED(st), WEXITSTATUS(st));
  /* Halde nach dem fork weiter benutzen */
  for (int i=0;i<50;i++){ char*t=malloc(64+i*7); memset(t,i,64); free(t); }
  printf("fork: halde nach fork ok\n");
  fflush(stdout);
  return 0;
}
