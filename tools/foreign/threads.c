#include <stdio.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#define N 4
#define RUNDEN 25000
static long zaehler[N];
static pthread_mutex_t m = PTHREAD_MUTEX_INITIALIZER;
static long gemeinsam = 0;
static void *arbeit(void *arg){
  long id = (long)arg;
  for (long i=0;i<RUNDEN;i++){
    zaehler[id]++;                 /* eigener Zaehler, kein Streit */
    pthread_mutex_lock(&m);        /* futex! */
    gemeinsam++;
    pthread_mutex_unlock(&m);
  }
  return (void*)(id*100);
}
int main(void){
  pthread_t t[N];
  printf("th: starte %d Faeden a %d Runden\n", N, RUNDEN); fflush(stdout);
  for (long i=0;i<N;i++){
    int rc = pthread_create(&t[i], 0, arbeit, (void*)i);
    if (rc){ printf("th: pthread_create %ld FEHLER rc=%d\n", i, rc); fflush(stdout); return 2; }
  }
  long summe=0;
  for (long i=0;i<N;i++){
    void *r=0; int rc = pthread_join(t[i], &r);
    if (rc){ printf("th: join %ld FEHLER rc=%d\n", i, rc); fflush(stdout); return 3; }
    summe += zaehler[i];
    printf("th: faden %ld fertig zaehler=%ld rueckgabe=%ld\n", i, zaehler[i], (long)r);
    fflush(stdout);
  }
  printf("th: summe=%ld erwartet=%d %s\n", summe, N*RUNDEN, summe==(long)N*RUNDEN?"OK":"FALSCH");
  printf("th: gemeinsam=%ld erwartet=%d %s\n", gemeinsam, N*RUNDEN, gemeinsam==(long)N*RUNDEN?"OK":"FALSCH");
  fflush(stdout);
  return 0;
}
