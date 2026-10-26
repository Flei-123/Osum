#ifndef BOOTREG_HITS_H
#define BOOTREG_HITS_H

#include "config.h"

#define MAX_HITS 16
#define DP_MAX 768

typedef struct {
    u8 dp[DP_MAX];
    u16 dp_len;
    u16 number;
    int existing;
} hit_t;

int hits_find(const config_t *cfg, handle_t own_volume, hit_t *hits, int max);

#endif
