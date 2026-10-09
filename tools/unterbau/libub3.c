/* foreign test library 3: thread-local storage in a dlopen'ed library */
__thread int ub3_tls = 7;
int ub3_get(void) { return ub3_tls; }
void ub3_set(int v) { ub3_tls = v; }
