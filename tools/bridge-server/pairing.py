import hmac
import secrets
import time

import legacy

CODE_TTL_S = float(legacy.env('BRIDGE_CODE_TTL_S', 600))
PENDING_MAX = int(legacy.env('BRIDGE_PENDING_MAX', 20))
WRONG_MAX = int(legacy.env('BRIDGE_WRONG_MAX', 5))
WRONG_WINDOW_S = float(legacy.env('BRIDGE_WRONG_WINDOW_S', 600))


class WrongCodeLimiter:

    def __init__(self, limit=WRONG_MAX, window_s=WRONG_WINDOW_S):
        self.limit = limit
        self.window_s = window_s
        self.stamps = []

    def prune(self, t):
        self.stamps = [s for s in self.stamps if t - s < self.window_s]

    def locked(self, t):
        self.prune(t)
        return len(self.stamps) >= self.limit

    def record_wrong(self, t):
        self.prune(t)
        self.stamps.append(t)
        return len(self.stamps) >= self.limit

    def clear(self):
        self.stamps = []


def code_valid(g, t):
    return bool(g.code) and t < g.code_expires


def pending_devices(devices, t):
    return [g for g in devices.values() if not g.paired and not g.blocked and code_valid(g, t)]


def taken_codes(devices, t):
    return {g.code for g in pending_devices(devices, t)}


def fresh_code(taken):
    while True:
        code = '%06d' % secrets.randbelow(1000000)
        if code not in taken:
            return code


def issue_code(devices, g, t):
    g.code = fresh_code(taken_codes(devices, t))
    g.code_time = t
    g.code_expires = t + CODE_TTL_S
    enforce_cap(devices, g, t)
    return g.code


def ensure_code(devices, g, t):
    if code_valid(g, t):
        return g.code
    return issue_code(devices, g, t)


def enforce_cap(devices, keep, t):
    waiting = sorted(pending_devices(devices, t), key=lambda x: x.code_time)
    while len(waiting) > PENDING_MAX:
        victim = waiting.pop(0)
        if victim is keep:
            continue
        victim.code = None
        if not (victim.paired or victim.blocked or victim.seen or victim.prev_seen):
            devices.pop(victim.device_id, None)


def reroll_all(devices, t):
    waiting = pending_devices(devices, t)
    for g in waiting:
        g.code = None
    for g in waiting:
        issue_code(devices, g, t)


def find_by_code(devices, code, t):
    match = None
    for g in pending_devices(devices, t):
        if hmac.compare_digest(g.code, code) and match is None:
            match = g
    return match


def pending_json(devices, t):
    items = []
    for g in sorted(pending_devices(devices, t), key=lambda x: x.code_time):
        items.append({'id': g.device_id, 'ip': g.info.get('ip_external', ''), 'info': g.info, 'age_s': round(t - g.code_time, 1)})
    return items


def forget_device(g):
    g.paired = False
    g.token = None
    g.challenge = None
    g.code = None
    g.seen = 0.0
    g.bye = False
