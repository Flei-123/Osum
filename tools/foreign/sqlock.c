#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include "sqlite3.h"
/* Zwei Prozesse, EINE Datenbank. Der Vater haelt eine Schreibtransaktion
   offen, das Kind versucht zu schreiben und MUSS SQLITE_BUSY bekommen --
   nicht die Datei zerstoeren. */
static const char *DB = "/w/sq.db";
int main(void){
  sqlite3 *db; char *err=0; int rc;
  printf("sq: sqlite %s\n", sqlite3_libversion()); fflush(stdout);
  if (sqlite3_open(DB,&db)) { printf("sq: open fehl\n"); fflush(stdout); return 1; }
  /* Kein Warten: wir WOLLEN die Absage sehen, nicht sie aussitzen. */
  sqlite3_busy_timeout(db, 0);
  rc = sqlite3_exec(db,"CREATE TABLE IF NOT EXISTS t(id INTEGER PRIMARY KEY, w TEXT);",0,0,&err);
  if(rc){ printf("sq: create fehl %s\n", err); fflush(stdout); return 1; }
  rc = sqlite3_exec(db,"INSERT INTO t(w) VALUES('vater');",0,0,&err);
  printf("sq: A insert rc=%d (%s)\n", rc, rc?err:"OK"); fflush(stdout);
  /* Schreibtransaktion AUFLASSEN -> die Datei ist gesperrt. */
  rc = sqlite3_exec(db,"BEGIN IMMEDIATE;",0,0,&err);
  printf("sq: A BEGIN IMMEDIATE rc=%d (%s)\n", rc, rc?err:"OK"); fflush(stdout);
  rc = sqlite3_exec(db,"INSERT INTO t(w) VALUES('in-transaktion');",0,0,&err);
  printf("sq: A insert in transaktion rc=%d\n", rc); fflush(stdout);

  pid_t p = fork();
  if (p==0){
    sqlite3 *d2; char *e2=0;
    if (sqlite3_open(DB,&d2)) { printf("sq: B open fehl\n"); fflush(stdout); _exit(1);} 
    sqlite3_busy_timeout(d2, 0);
    int r = sqlite3_exec(d2,"INSERT INTO t(w) VALUES('kind');",0,0,&e2);
    printf("sq: B insert rc=%d %s %s\n", r,
       sqlite3_errstr(r),
       (r==SQLITE_BUSY||r==SQLITE_LOCKED)?"BUSY-RICHTIG":"FALSCH-SOLLTE-BUSY-SEIN");
    fflush(stdout);
    sqlite3_close(d2);
    _exit(r==SQLITE_BUSY||r==SQLITE_LOCKED ? 0 : 9);
  }
  int st=0; wait(&st);
  printf("sq: kind endete code=%d\n", WEXITSTATUS(st)); fflush(stdout);
  rc = sqlite3_exec(db,"COMMIT;",0,0,&err);
  printf("sq: A COMMIT rc=%d\n", rc); fflush(stdout);

  /* Jetzt ist frei: das naechste Kind MUSS schreiben koennen. */
  pid_t q = fork();
  if (q==0){
    sqlite3 *d3; char *e3=0;
    if (sqlite3_open(DB,&d3)) { printf("sq: C open fehl\n"); fflush(stdout); _exit(1);} 
    sqlite3_busy_timeout(d3, 0);
    int r = sqlite3_exec(d3,"INSERT INTO t(w) VALUES('kind-nach-commit');",0,0,&e3);
    printf("sq: C insert rc=%d %s\n", r, r==0?"GEWAEHRT-RICHTIG":"FALSCH");
    fflush(stdout); sqlite3_close(d3); _exit(r?9:0);
  }
  wait(&st);
  printf("sq: kind2 endete code=%d\n", WEXITSTATUS(st)); fflush(stdout);
  /* Und die Datenbank ist HEIL: zaehlen. */
  sqlite3_stmt *stm;
  if (sqlite3_prepare_v2(db,"SELECT COUNT(*) FROM t;",-1,&stm,0)==SQLITE_OK){
    if (sqlite3_step(stm)==SQLITE_ROW)
      printf("sq: zeilen=%d (erwartet 3)\n", sqlite3_column_int(stm,0));
    sqlite3_finalize(stm);
  }
  rc = sqlite3_exec(db,"PRAGMA integrity_check;",0,0,&err);
  printf("sq: integrity_check rc=%d %s\n", rc, rc?err:"OK");
  fflush(stdout);
  sqlite3_close(db);
  printf("sq: fertig\n"); fflush(stdout);
  return 0;
}
