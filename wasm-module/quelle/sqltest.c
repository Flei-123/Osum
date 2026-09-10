/* Ein Programm, das SQLite benutzt. SQLite selbst ist UNVERAENDERT
   die Amalgamation 3.45.0 vom SQLite-Team. */
#include <stdio.h>
#include "sqlite3.h"

static int zeile(void *n, int spalten, char **wert, char **name) {
    (void)name;
    printf("  zeile:");
    for (int i = 0; i < spalten; i++)
        printf(" %s", wert[i] ? wert[i] : "NULL");
    printf("\n");
    (*(int*)n)++;
    return 0;
}

int main(void) {
    sqlite3 *db;
    char *fehler = 0;
    int n = 0;

    printf("SQLite-Version: %s\n", sqlite3_libversion());

    if (sqlite3_open("/osum-test.db", &db) != SQLITE_OK) {
        printf("open fehlgeschlagen: %s\n", sqlite3_errmsg(db));
        return 1;
    }
    printf("datenbank offen\n");

    const char *sql =
        "CREATE TABLE IF NOT EXISTS geraete(id INTEGER PRIMARY KEY, name TEXT, jahr INT);"
        "INSERT INTO geraete(name,jahr) VALUES('OrientOS',2026);"
        "INSERT INTO geraete(name,jahr) VALUES('Firn',2025);"
        "INSERT INTO geraete(name,jahr) VALUES('WASM-Schleuse',2026);";
    if (sqlite3_exec(db, sql, 0, 0, &fehler) != SQLITE_OK) {
        printf("exec fehlgeschlagen: %s\n", fehler);
        return 1;
    }
    printf("tabelle angelegt, 3 zeilen eingefuegt\n");

    if (sqlite3_exec(db, "SELECT id,name,jahr FROM geraete ORDER BY id;",
                     zeile, &n, &fehler) != SQLITE_OK) {
        printf("select fehlgeschlagen: %s\n", fehler);
        return 1;
    }
    printf("zeilen gelesen: %d\n", n);

    n = 0;
    sqlite3_exec(db, "SELECT name FROM geraete WHERE jahr=2026 ORDER BY name;",
                 zeile, &n, &fehler);
    printf("davon aus 2026: %d\n", n);

    sqlite3_close(db);
    printf("datenbank zu\n");
    return 0;
}
