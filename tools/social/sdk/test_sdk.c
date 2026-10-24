#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "orient_social.h"

int main(void)
{
    char target[64];

    assert(orient_set_activity("Minecraft", 0, "mc://h:1") == ORIENT_SOCIAL_OK);
    assert(orient_set_activity("Pong", 1, NULL) == ORIENT_SOCIAL_OK);
    assert(orient_set_activity("Solo", 0, NULL) == ORIENT_SOCIAL_OK);
    assert(orient_set_activity("", 0, NULL) == ORIENT_SOCIAL_FAIL);
    assert(orient_set_activity("bad\nname", 0, NULL) == ORIENT_SOCIAL_FAIL);
    assert(orient_clear_activity() == ORIENT_SOCIAL_OK);
    assert(orient_invite("local:peter", "Chess") == ORIENT_SOCIAL_OK);
    assert(orient_invite("local:peter", NULL) == ORIENT_SOCIAL_OK);
    assert(orient_invite("", NULL) == ORIENT_SOCIAL_FAIL);
    assert(orient_ask_to_join("local:peter") == ORIENT_SOCIAL_OK);
    assert(orient_take_join("Chess", target, sizeof target) == 1);
    printf("target=%s\n", target);
    assert(strcmp(target, "game://lobby/7") == 0);
    assert(orient_take_join(NULL, target, 4) == 1);
    assert(strcmp(target, "gam") == 0);
    puts("c-ok");
    return 0;
}
