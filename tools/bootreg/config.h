#ifndef BOOTREG_CONFIG_H
#define BOOTREG_CONFIG_H

#include "efi.h"

#define MAX_ALT 6

typedef struct {
    char slug[48];
    char alt[MAX_ALT][48];
    int n_alt;
    char file[48];
    char name[96];
    u16 name16[96];
    int list_mode;
} config_t;

u64 config_load(handle_t volume, config_t *cfg);

#endif
