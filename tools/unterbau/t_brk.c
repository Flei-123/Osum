#define TNAME "brk"
#include "t.h"
#include <sys/syscall.h>
#include <unistd.h>

#define PAGE 4096UL

static char *brk_to(char *addr)
{
    return (char *)syscall(SYS_brk, addr);
}

int main(void)
{
    char *base = brk_to(0);
    CHECK("query", base != 0 && (long)base > 0, "base=%p", (void *)base);

    long grown = 0;
    for (long p = 1; p <= 64; p++) {
        char *end = brk_to(base + p * PAGE);
        if (end != base + p * PAGE) break;
        end[-1] = 1;
        grown = p;
    }
    CHECK("grow_page_by_page", grown == 64, "grown=%ld", grown);

    char *cur = brk_to(0);
    char *big = brk_to(base + 4 * 1024 * 1024);
    if (big == base + 4 * 1024 * 1024) {
        big[-1] = 7;
        base[100 * PAGE] = 9;
        CHECK("touch_far_pages", big[-1] == 7 && base[100 * PAGE] == 9, "ok");
        PASS("grow_one_call_4mib");
    } else if (big == cur) {
        GAP("grow_one_call_4mib", "brk window is full, heap stays at %p", (void *)cur);
    } else {
        FAIL("grow_one_call_4mib", "partial growth got=%p cur=%p", (void *)big, (void *)cur);
    }

    char *small = brk_to(base + 10 * PAGE + 17);
    CHECK("shrink_unaligned", small == base + 10 * PAGE + 17, "got=%p", (void *)small);
    CHECK("query_after_shrink", brk_to(0) == base + 10 * PAGE + 17, "cur=%p", (void *)brk_to(0));

    char *regrow = brk_to(base + 20 * PAGE);
    int zero = regrow == base + 20 * PAGE;
    for (long i = 11 * PAGE; zero && i < 20 * PAGE; i += 512)
        if (base[i] != 0) zero = 0;
    CHECK("regrow_zeroed", zero, "regrow=%p", (void *)regrow);

    CHECK("back_to_base", brk_to(base) == base, "cur=%p", (void *)brk_to(0));
    return 0;
}
