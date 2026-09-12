#include <stdio.h>
#include "sqlite3.h"
static int cb(void *u,int n,char **v,char **c){
    for(int i=0;i<n;i++) printf("%s=%s%s", c[i], v[i]?v[i]:"NULL", i+1<n?"  ":"\n");
    return 0;
}
int main(void){
    sqlite3 *db; char *err=0; int rc;
    printf("sqlite version: %s\n", sqlite3_libversion());
    rc = sqlite3_open("/w/test.db", &db);
    if(rc){ printf("open failed: %s\n", sqlite3_errmsg(db)); return 1; }
    printf("db open ok\n");
    const char *sql =
      "CREATE TABLE leute(id INTEGER PRIMARY KEY, name TEXT, ort TEXT);"
      "INSERT INTO leute(name,ort) VALUES('Justin','Polling');"
      "INSERT INTO leute(name,ort) VALUES('Osum','Mieming');"
      "INSERT INTO leute(name,ort) VALUES('Firn','Tirol');";
    rc = sqlite3_exec(db, sql, 0,0,&err);
    if(rc!=SQLITE_OK){ printf("exec failed: %s\n", err); return 1; }
    printf("table + 3 inserts ok\n");
    rc = sqlite3_exec(db, "SELECT id,name,ort FROM leute ORDER BY id;", cb,0,&err);
    if(rc!=SQLITE_OK){ printf("select failed: %s\n", err); return 1; }
    rc = sqlite3_exec(db, "SELECT COUNT(*) AS anzahl FROM leute;", cb,0,&err);
    if(rc!=SQLITE_OK){ printf("count failed: %s\n", err); return 1; }
    sqlite3_close(db);
    printf("sqlite ok\n");
    return 0;
}
