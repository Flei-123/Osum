#ifndef BOOTREG_BOOTVARS_H
#define BOOTREG_BOOTVARS_H

#include "config.h"
#include "hits.h"

u64 bootvars_register(const config_t *cfg, hit_t *hits, int n_hits);
u64 bootvars_list(void);

#endif
