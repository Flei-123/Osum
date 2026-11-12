/* SPDX-License-Identifier: GPL-2.0-only
 * static non-PIE holder: owns a low page directory until its stdin closes. */
#include <unistd.h>

static char pad[64] = { 1 };

int main(void)
{
    char c;
    (void)!write(1, "r", 1);
    while (read(0, &c, 1) > 0) pad[0] = c;
    return pad[1];
}
