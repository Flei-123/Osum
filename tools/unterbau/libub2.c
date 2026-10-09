/* foreign test library 2: needs libub1.so (DT_NEEDED), calls into it */
int ub1_add(int, int);
int ub2_call(int x) { return ub1_add(x, 100); }
