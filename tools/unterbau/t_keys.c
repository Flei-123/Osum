#define TNAME "keys"
#include "t.h"
#include <stdint.h>
#include <sys/syscall.h>

#define NR_ADD_KEY 248
#define NR_REQUEST_KEY 249
#define NR_KEYCTL 250
#define KEY_SPEC_SESSION_KEYRING (-3)
#define KEY_SPEC_PROCESS_KEYRING (-2)
#define KEYCTL_GET_KEYRING_ID 0
#define KEYCTL_JOIN_SESSION_KEYRING 1
#define KEYCTL_UPDATE 2
#define KEYCTL_REVOKE 3
#define KEYCTL_DESCRIBE 6
#define KEYCTL_CLEAR 7
#define KEYCTL_LINK 8
#define KEYCTL_UNLINK 9
#define KEYCTL_SEARCH 10
#define KEYCTL_READ 11
#define KEYCTL_INVALIDATE 21
#define ENOKEY_NUM 126
#define EKEYREVOKED_NUM 128
#define BUF_BYTES 128

static long raw(long nr, long a, long b, long c, long d, long e)
{
    errno = 0;
    return syscall(nr, a, b, c, d, e, 0);
}

static long ctl(long cmd, long a, long b, long c, long d)
{
    return raw(NR_KEYCTL, cmd, a, b, c, d);
}

static void add_checks(long ring)
{
    long key = raw(NR_ADD_KEY, (long)"user", (long)"alpha", (long)"secret", 6, ring);
    CHECKC("add_user_key", key > 0);
    long again = raw(NR_ADD_KEY, (long)"user", (long)"alpha", (long)"other", 5, ring);
    CHECK("add_same_description_updates", again == key, "key=%ld again=%ld", key, again);
    char buf[BUF_BYTES];
    memset(buf, 0, sizeof buf);
    long r = ctl(KEYCTL_READ, key, (long)buf, sizeof buf, 0);
    CHECK("read_user_key", r == 5 && !memcmp(buf, "other", 5), "r=%ld buf=%s", r, buf);
    r = ctl(KEYCTL_READ, key, (long)buf, 2, 0);
    CHECK("read_short_buffer_returns_full_length", r == 5 && !memcmp(buf, "ot", 2), "r=%ld", r);
    r = ctl(KEYCTL_UPDATE, key, (long)"fresh", 5, 0);
    CHECK("update_key", r == 0, "r=%ld errno=%d", r, errno);
    r = ctl(KEYCTL_READ, key, (long)buf, sizeof buf, 0);
    CHECK("read_after_update", r == 5 && !memcmp(buf, "fresh", 5), "r=%ld", r);
    r = ctl(KEYCTL_DESCRIBE, key, (long)buf, sizeof buf, 0);
    CHECK("describe_key", r > 0 && !strncmp(buf, "user;", 5) && strstr(buf, ";alpha") != 0, "r=%ld buf=%s", r, buf);
    r = raw(NR_ADD_KEY, (long)"nosuchtype", (long)"x", (long)"y", 1, ring);
    CHECK("add_unknown_type", r == -1 && errno == ENODEV, "r=%ld errno=%d", r, errno);
    r = raw(NR_ADD_KEY, (long)"user", (long)"", (long)"y", 1, ring);
    CHECK("add_empty_description", r == -1 && errno == EINVAL, "r=%ld errno=%d", r, errno);
    r = raw(NR_ADD_KEY, (long)"user", (long)"empty", (long)"y", 0, ring);
    CHECK("add_empty_payload", r == -1 && errno == EINVAL, "r=%ld errno=%d", r, errno);
    r = raw(NR_ADD_KEY, (long)"logon", (long)"nocolon", (long)"y", 1, ring);
    CHECK("add_logon_needs_colon", r == -1 && errno == EINVAL, "r=%ld errno=%d", r, errno);
    long logon = raw(NR_ADD_KEY, (long)"logon", (long)"svc:name", (long)"pw", 2, ring);
    CHECKC("add_logon_key", logon > 0);
    r = ctl(KEYCTL_READ, logon, (long)buf, sizeof buf, 0);
    CHECK("logon_unreadable", r == -1 && errno == EOPNOTSUPP, "r=%ld errno=%d", r, errno);
    r = raw(NR_ADD_KEY, (long)"user", (long)"badring", (long)"y", 1, 0x7fff0000);
    CHECK("add_bad_ring", r == -1 && errno == ENOKEY_NUM, "r=%ld errno=%d", r, errno);
    r = raw(NR_ADD_KEY, (long)"user", (long)"badring", 1, 1, ring);
    CHECK("add_bad_payload_pointer", r == -1 && errno == EFAULT, "r=%ld errno=%d", r, errno);
    r = ctl(KEYCTL_READ, 0x7fff0000, (long)buf, sizeof buf, 0);
    CHECK("read_missing_key", r == -1 && errno == ENOKEY_NUM, "r=%ld errno=%d", r, errno);
}

static void request_checks(long ring)
{
    long key = raw(NR_ADD_KEY, (long)"user", (long)"findme", (long)"v", 1, ring);
    long r = raw(NR_REQUEST_KEY, (long)"user", (long)"findme", 0, 0, 0);
    CHECK("request_finds_key", r == key, "r=%ld key=%ld", r, key);
    r = raw(NR_REQUEST_KEY, (long)"user", (long)"missing", 0, 0, 0);
    CHECK("request_missing_enokey", r == -1 && errno == ENOKEY_NUM, "r=%ld errno=%d", r, errno);
    r = ctl(KEYCTL_SEARCH, ring, (long)"user", (long)"findme", 0);
    CHECK("search_in_ring", r == key, "r=%ld key=%ld", r, key);
    long other = ctl(KEYCTL_JOIN_SESSION_KEYRING, (long)"tkeys-ring", 0, 0, 0);
    CHECKC("join_named_session", other > 0);
    r = ctl(KEYCTL_SEARCH, other, (long)"user", (long)"findme", 0);
    CHECK("search_other_ring_misses", r == -1 && errno == ENOKEY_NUM, "r=%ld errno=%d", r, errno);
    r = ctl(KEYCTL_LINK, key, other, 0, 0);
    CHECK("link_key", r == 0, "r=%ld errno=%d", r, errno);
    r = ctl(KEYCTL_SEARCH, other, (long)"user", (long)"findme", 0);
    CHECK("search_after_link", r == key, "r=%ld key=%ld", r, key);
    r = ctl(KEYCTL_UNLINK, key, other, 0, 0);
    CHECK("unlink_key", r == 0, "r=%ld errno=%d", r, errno);
    r = ctl(KEYCTL_UNLINK, key, other, 0, 0);
    CHECK("unlink_twice_enoent", r == -1 && errno == ENOENT, "r=%ld errno=%d", r, errno);
    char buf[BUF_BYTES];
    r = ctl(KEYCTL_READ, other, (long)buf, sizeof buf, 0);
    CHECK("read_empty_keyring", r == 0, "r=%ld", r);
    ctl(KEYCTL_LINK, key, other, 0, 0);
    uint32_t serial = 0;
    r = ctl(KEYCTL_READ, other, (long)&serial, sizeof serial, 0);
    CHECK("read_keyring_lists_serials", r == 4 && serial == (uint32_t)key, "r=%ld serial=%u", r, serial);
    r = ctl(KEYCTL_CLEAR, other, 0, 0, 0);
    CHECK("clear_keyring", r == 0, "r=%ld errno=%d", r, errno);
    r = ctl(KEYCTL_CLEAR, key, 0, 0, 0);
    CHECK("clear_non_keyring", r == -1 && errno == ENOTDIR, "r=%ld errno=%d", r, errno);
}

static void revoke_checks(long ring)
{
    long key = raw(NR_ADD_KEY, (long)"user", (long)"doomed", (long)"v", 1, ring);
    long r = ctl(KEYCTL_REVOKE, key, 0, 0, 0);
    CHECK("revoke_key", r == 0, "r=%ld errno=%d", r, errno);
    char buf[BUF_BYTES];
    r = ctl(KEYCTL_READ, key, (long)buf, sizeof buf, 0);
    CHECK("read_revoked", r == -1 && errno == EKEYREVOKED_NUM, "r=%ld errno=%d", r, errno);
    key = raw(NR_ADD_KEY, (long)"user", (long)"gone", (long)"v", 1, ring);
    r = ctl(KEYCTL_INVALIDATE, key, 0, 0, 0);
    CHECK("invalidate_key", r == 0, "r=%ld errno=%d", r, errno);
    r = ctl(KEYCTL_READ, key, (long)buf, sizeof buf, 0);
    CHECK("read_invalidated", r == -1 && errno == ENOKEY_NUM, "r=%ld errno=%d", r, errno);
    r = ctl(999, 0, 0, 0, 0);
    CHECK("unknown_command", r == -1 && errno == EOPNOTSUPP, "r=%ld errno=%d", r, errno);
}

int main(void)
{
    long ring = ctl(KEYCTL_GET_KEYRING_ID, KEY_SPEC_SESSION_KEYRING, 1, 0, 0);
    CHECKC("session_keyring_id", ring > 0);
    if (ring <= 0)
        return 0;
    long again = ctl(KEYCTL_GET_KEYRING_ID, KEY_SPEC_SESSION_KEYRING, 0, 0, 0);
    CHECK("session_keyring_stable", again == ring, "ring=%ld again=%ld", ring, again);
    long proc = ctl(KEYCTL_GET_KEYRING_ID, KEY_SPEC_PROCESS_KEYRING, 1, 0, 0);
    CHECK("process_keyring_differs", proc > 0 && proc != ring, "proc=%ld ring=%ld", proc, ring);
    add_checks(ring);
    request_checks(ring);
    revoke_checks(ring);
    return 0;
}
