/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef ORIENT_SOCIAL_H
#define ORIENT_SOCIAL_H

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>

#define ORIENT_SOCIAL_OK 0
#define ORIENT_SOCIAL_FAIL (-1)
#define ORIENT_SOCIAL_MAX_ARGS 12
#define ORIENT_SOCIAL_REPLY_MAX 4096

static inline int orient_social_valid(const char *s)
{
    return s && *s && !strchr(s, '\n');
}

static inline int orient_social_call(const char *action, const char *const *kv, int nkv, char *reply, size_t cap)
{
    const char *act = getenv("ORIENT_ACT");
    char *argv[ORIENT_SOCIAL_MAX_ARGS + 4];
    int fds[2];
    int argc = 0;
    size_t len = 0;
    int status = 0;
    pid_t pid;

    if (!act || !*act)
        act = "/bin/act";
    if (!action || nkv > ORIENT_SOCIAL_MAX_ARGS)
        return ORIENT_SOCIAL_FAIL;
    argv[argc++] = (char *)act;
    argv[argc++] = (char *)"call";
    argv[argc++] = (char *)action;
    for (int i = 0; i < nkv; i++) {
        if (!orient_social_valid(kv[i]) || !strchr(kv[i], '='))
            return ORIENT_SOCIAL_FAIL;
        argv[argc++] = (char *)kv[i];
    }
    argv[argc] = NULL;
    if (pipe(fds) != 0)
        return ORIENT_SOCIAL_FAIL;
    pid = fork();
    if (pid < 0) {
        close(fds[0]);
        close(fds[1]);
        return ORIENT_SOCIAL_FAIL;
    }
    if (pid == 0) {
        close(fds[0]);
        dup2(fds[1], 1);
        close(fds[1]);
        execv(act, argv);
        _exit(127);
    }
    close(fds[1]);
    if (reply && cap)
        reply[0] = 0;
    for (;;) {
        char buf[256];
        ssize_t n = read(fds[0], buf, sizeof buf);
        if (n <= 0)
            break;
        if (reply && len + (size_t)n < cap) {
            memcpy(reply + len, buf, (size_t)n);
            len += (size_t)n;
            reply[len] = 0;
        }
    }
    close(fds[0]);
    if (waitpid(pid, &status, 0) < 0)
        return ORIENT_SOCIAL_FAIL;
    return WIFEXITED(status) && WEXITSTATUS(status) == 0 ? ORIENT_SOCIAL_OK : ORIENT_SOCIAL_FAIL;
}

static inline int orient_social_field(const char *reply, const char *key, char *out, size_t cap)
{
    size_t kn = strlen(key);
    const char *p = reply;

    while (p && *p) {
        const char *e = strchr(p, '\n');
        size_t ln = e ? (size_t)(e - p) : strlen(p);
        if (ln > kn && !strncmp(p, key, kn) && p[kn] == '=') {
            size_t vn = ln - kn - 1;
            if (vn >= cap)
                vn = cap - 1;
            memcpy(out, p + kn + 1, vn);
            out[vn] = 0;
            return 1;
        }
        p = e ? e + 1 : NULL;
    }
    return 0;
}

static inline int orient_set_activity(const char *name, int joinable, const char *party)
{
    char a[ORIENT_SOCIAL_REPLY_MAX / 8], b[ORIENT_SOCIAL_REPLY_MAX / 8];
    const char *kv[3];
    int n = 0;

    if (!orient_social_valid(name))
        return ORIENT_SOCIAL_FAIL;
    snprintf(a, sizeof a, "name=%s", name);
    kv[n++] = a;
    if (joinable || orient_social_valid(party))
        kv[n++] = "join=true";
    if (orient_social_valid(party)) {
        snprintf(b, sizeof b, "party=%s", party);
        kv[n++] = b;
    }
    return orient_social_call("social.activity.set", kv, n, NULL, 0);
}

static inline int orient_clear_activity(void)
{
    return orient_social_call("social.activity.clear", NULL, 0, NULL, 0);
}

static inline int orient_social_invite(const char *friend_id, const char *kind, const char *name)
{
    char a[ORIENT_SOCIAL_REPLY_MAX / 8], b[ORIENT_SOCIAL_REPLY_MAX / 8], c[64];
    const char *kv[3];
    int n = 0;

    if (!orient_social_valid(friend_id))
        return ORIENT_SOCIAL_FAIL;
    snprintf(a, sizeof a, "id=%s", friend_id);
    snprintf(c, sizeof c, "kind=%s", kind);
    kv[n++] = a;
    kv[n++] = c;
    if (orient_social_valid(name)) {
        snprintf(b, sizeof b, "name=%s", name);
        kv[n++] = b;
    }
    return orient_social_call("social.invites.send", kv, n, NULL, 0);
}

static inline int orient_invite(const char *friend_id, const char *name)
{
    return orient_social_invite(friend_id, "invite", name);
}

static inline int orient_ask_to_join(const char *friend_id)
{
    return orient_social_invite(friend_id, "join", NULL);
}

static inline int orient_take_join(const char *name, char *target, size_t cap)
{
    char reply[ORIENT_SOCIAL_REPLY_MAX], a[ORIENT_SOCIAL_REPLY_MAX / 8], found[8];
    const char *kv[1];
    int n = 0;

    if (!target || !cap)
        return ORIENT_SOCIAL_FAIL;
    target[0] = 0;
    if (orient_social_valid(name)) {
        snprintf(a, sizeof a, "name=%s", name);
        kv[n++] = a;
    }
    if (orient_social_call("social.party.take", kv, n, reply, sizeof reply) != ORIENT_SOCIAL_OK)
        return ORIENT_SOCIAL_FAIL;
    if (!orient_social_field(reply, "found", found, sizeof found) || strcmp(found, "true"))
        return 0;
    return orient_social_field(reply, "target", target, cap) ? 1 : ORIENT_SOCIAL_FAIL;
}

#endif
