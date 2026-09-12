/* Osum entry shim.
 *
 * Osum starts a program the way `kernel/elf.fi` describes it: the
 * argument block in RDI, and NOTHING else -- no auxiliary vector. musl
 * needs one: `__init_libc` reads `AT_PAGESZ` out of it and stores it in
 * `libc.page_size`, and its malloc dereferences `libc.auxv`
 * unconditionally. Without it the first `malloc` reads through a null
 * pointer (measured: `err=0x5 cr2=0x0` in `__malloc_alloc_meta`).
 *
 * So the auxv is built HERE, on the stack of the first function, and
 * musl is initialised with it exactly as a Linux kernel would.
 */
#include <stddef.h>

#define AT_NULL   0
#define AT_PHDR   3
#define AT_PHENT  4
#define AT_PHNUM  5
#define AT_PAGESZ 6
#define AT_BASE   7
#define AT_ENTRY  9
#define AT_UID   11
#define AT_EUID  12
#define AT_GID   13
#define AT_EGID  14
#define AT_HWCAP 16
#define AT_CLKTCK 17
#define AT_SECURE 23
#define AT_RANDOM 25

extern int main(int, char**, char**);
/* musl's own initialiser: takes argv and builds everything from the
 * block that follows it -- envp, then the auxv behind the envp NUL. */
extern void __init_libc(char **envp, char *pn);

/* The ELF header of this very program. The linker script puts it at the
 * start of the first segment (FILEHDR PHDRS), so the program headers can
 * be handed to musl the way a Linux kernel hands them over. */
extern char __ehdr_start[] __attribute__((weak));

static char *fake_env[1] = { 0 };

long osum_main(long argc, char **argv, char **envp)
{
    /* musl walks: argv[0..argc-1], NUL, envp[...], NUL, then auxv.
     * Osum's block does not have that shape, so a proper one is built. */
    static char *blk[8 + 2 * 16];
    size_t *aux;
    int i = 0, n = 0;

    if (!argv) { argv = fake_env; argc = 0; }
    if (!envp) envp = fake_env;

    /* envp, terminated */
    while (envp[n] && n < 8) { blk[i++] = envp[n]; n++; }
    blk[i++] = 0;

    aux = (size_t *)&blk[i];
    #define AUX(k, v) do { *aux++ = (size_t)(k); *aux++ = (size_t)(v); } while (0)
    AUX(AT_PAGESZ, 4096);
    AUX(AT_UID, 0); AUX(AT_EUID, 0); AUX(AT_GID, 0); AUX(AT_EGID, 0);
    AUX(AT_SECURE, 0);
    AUX(AT_CLKTCK, 100);
    if (&__ehdr_start[0]) {
        AUX(AT_PHDR,  __ehdr_start + 64);   /* PHDRS follow the ELF header */
        AUX(AT_PHENT, 56);
        AUX(AT_PHNUM, 3);
    }
    AUX(AT_NULL, 0);
    #undef AUX

    __init_libc((char **)blk, argv[0] ? argv[0] : "osum");
    return (long)main((int)argc, argv, envp);
}
