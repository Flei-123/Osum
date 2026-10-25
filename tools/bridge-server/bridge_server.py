import argparse
import datetime
import hashlib
import hmac
import http.server
import base64
import json
import os
import re
import secrets
import socketserver
import sys
import threading
import time

import legacy
import pairing

JOB_KINDS = ('system', 'screenshot', 'run', 'read', 'write', 'list', 'log', 'key', 'mouse', 'click', 'scan', 'input')
MAX_BODY = 24 * 1024 * 1024
MAX_VALUE = 1500000
MAX_JOB_BODY = 2100 * 1024
WAIT_S = 25.0
TOKEN_TTL_S = 12 * 3600
DEAD_S = 90
KEEP_RESULTS = 300
WIRE_DEAD_S = 300
DEAD_S = int(legacy.env('BRIDGE_DEAD_S', DEAD_S))
JOB_TTL_S = int(legacy.env('BRIDGE_JOB_TTL_S', 900))
BUSY_GRACE_S = int(legacy.env('BRIDGE_BUSY_GRACE_S', 1320))
WATCHDOG_S = float(legacy.env('BRIDGE_WATCHDOG_S', 5))
EVENT_MAX = 80
STATUS_NAME = 'status.json'
_lock = threading.RLock()
_devices = {}
_root = '/srv/bruecke'

def sanitize(s, limit=64):
    s = re.sub('[^A-Za-z0-9._-]', '', s or '')
    s = s.strip('.-') or 'unknown'
    return s[:limit]

def now():
    return time.time()

def timestamp():
    return datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')

def log(text):
    sys.stderr.write('[bridge] %s %s\n' % (timestamp(), text))
    sys.stderr.flush()
try:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    from cryptography.exceptions import InvalidSignature
    HAS_ED25519 = True
except Exception:
    HAS_ED25519 = False

def verify_signature(pubkey_hex, message, sig_hex):
    if not HAS_ED25519:
        return None
    try:
        raw = bytes.fromhex(pubkey_hex or '')
        sig = bytes.fromhex(sig_hex or '')
    except ValueError:
        return False
    if len(raw) != 32 or len(sig) != 64:
        return False
    try:
        Ed25519PublicKey.from_public_bytes(raw).verify(sig, message)
        return True
    except InvalidSignature:
        return False
    except Exception:
        return False

def signature_ok(g, device_id, challenge, sig):
    try:
        raw_challenge = bytes.fromhex(challenge)
    except ValueError:
        raw_challenge = b''
    messages = [raw_challenge] + [(prefix + device_id + ':' + challenge).encode() for prefix in legacy.SIGN_PREFIXES]
    if HAS_ED25519:
        return any((verify_signature(g.pubkey, m, sig) for m in messages))
    if not g.secret:
        return None
    key = bytes.fromhex(g.secret)
    return any((hmac.compare_digest(hmac.new(key, m, hashlib.sha256).hexdigest(), sig) for m in messages))

class Device:

    def __init__(self, device_id):
        self.device_id = device_id
        self.pubkey = None
        self.secret = None
        self.paired = False
        self.blocked = False
        self.code = None
        self.code_time = 0.0
        self.code_expires = 0.0
        self.challenge = None
        self.token = None
        self.token_until = 0.0
        self.seen = 0.0
        self.since = 0.0
        self.info = {}
        self.jobs = []
        self.results = {}
        self.counter = 0
        self.waker = threading.Condition(_lock)
        self.mac = ''
        self.last_ip = ''
        self.sessions = 0
        self.polls = 0
        self.max_gap = 0.0
        self.bye = False
        self.running = None
        self.last_job = None
        self.end_reason = ''
        self.end_time = 0.0
        self.events = []
        self.old_state = 'never'
        self.prev_seen = 0.0
        self.session_end_reported = True
        self.knocks = 0
        self.knock_since = 0.0
        self.knock_time = 0.0
        self.hello_time = 0.0

    def alive(self):
        return now() - self.seen < DEAD_S

    def to_json(self):
        return {'device_id': self.device_id, 'paired': self.paired, 'blocked': self.blocked, 'connected': self.alive(), 'last_seen_s': round(now() - self.seen, 1) if self.seen else None, 'connected_since_s': round(now() - self.since, 1) if self.since else None, 'open_jobs': len(self.jobs), 'info': self.info, 'state': state(self), 'last_contact_utc': utc_text(self.seen or self.prev_seen), 'mac': self.mac}

def utc_text(t):
    if not t:
        return None
    return datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')

def vienna_text(t):
    if not t:
        return None
    try:
        import zoneinfo
        z = zoneinfo.ZoneInfo('Europe/Vienna')
        return datetime.datetime.fromtimestamp(t, z).strftime('%Y-%m-%d %H:%M:%S %Z')
    except Exception:
        return None

def event(g, text, loud=True):
    with _lock:
        g.events.append([round(now(), 1), text])
        del g.events[:-EVENT_MAX]
    if loud:
        log('%s: %s' % (g.device_id, text))

def state(g):
    if g.knock_time and now() - g.knock_time < 150 and (g.knock_time > g.hello_time) and (g.knock_time > (g.seen or 0)):
        return 'knocking'
    if not g.seen and (not g.prev_seen):
        return 'never'
    if g.seen and g.alive():
        return 'online'
    if g.seen and g.running and (now() - g.running.get('since', 0) < BUSY_GRACE_S) and (now() - g.seen < BUSY_GRACE_S):
        return 'busy'
    if g.seen and g.bye:
        return 'clean_exit'
    return 'silent'

def poll_seen(g):
    with _lock:
        t = now()
        if g.seen:
            gap = t - g.seen
            if gap > g.max_gap:
                g.max_gap = gap
            if gap > DEAD_S and g.since and (not g.bye):
                reason = 'Gap of %d s between two reports' % gap
                if g.running:
                    reason += ' (job %s %s was running)' % (g.running.get('id'), g.running.get('kind'))
                event(g, reason)
        g.seen = t
        g.polls += 1
        g.bye = False

def session_begins(g, ip):
    with _lock:
        t = now()
        if g.seen and (not g.session_end_reported):
            duration = g.seen - g.since if g.since else 0
            silence = t - g.seen
            event(g, 'NEW SESSION after %d s without a report: the previous one (%d s, %d reports, longest gap %d s) ended without a logout%s' % (silence, duration, g.polls, g.max_gap, '; job %s %s was unanswered' % (g.running.get('id'), g.running.get('kind')) if g.running else ''))
        elif not g.seen and g.prev_seen:
            event(g, 'FIRST SESSION after server start; last contact before: %s (%d s ago)' % (utc_text(g.prev_seen), t - g.prev_seen))
        if g.running:
            event(g, 'Job %s %s was lost with the old session' % (g.running.get('id'), g.running.get('kind')))
            g.running = None
        g.sessions += 1
        g.polls = 0
        g.max_gap = 0.0
        g.bye = False
        g.last_ip = ip
        g.end_reason = ''
        g.session_end_reported = False
        g.old_state = 'online'
        drop_stale(g)
        status_write()

def drop_stale(g):
    with _lock:
        t = now()
        kept = []
        for a in g.jobs:
            ttl = a.get('ttl_s', JOB_TTL_S)
            if ttl and t - a.get('ts', t) > ttl:
                event(g, 'JOB DROPPED (stale, %d s old): id=%s kind=%s' % (t - a.get('ts', t), a.get('id'), a.get('kind')))
            else:
                kept.append(a)
        g.jobs[:] = kept

def job_dispatched(g, a):
    with _lock:
        g.running = {'id': a.get('id'), 'kind': a.get('kind'), 'since': now()}
        g.last_job = {'id': a.get('id'), 'kind': a.get('kind'), 'status': 'running', 'from': now(), 'until': None}

def job_done(g, aid, status):
    with _lock:
        la = g.running
        if la and str(la.get('id')) == str(aid):
            g.running = None
        if g.last_job and str(g.last_job.get('id')) == str(aid):
            g.last_job['status'] = status
            g.last_job['until'] = now()

def status_path():
    return os.path.join(_root, STATUS_NAME)

def status_write():
    with _lock:
        d = {'_server_start': SERVER_START}
        for k, g in _devices.items():
            if not (g.seen or g.prev_seen or g.events or g.knock_time):
                continue
            d[k] = {'seen': g.seen or g.prev_seen, 'ip': g.last_ip, 'since': g.since, 'commit': (g.info or {}).get('commit', ''), 'sessions': g.sessions, 'polls': g.polls, 'max_gap': g.max_gap, 'bye': g.bye, 'running': g.running, 'last_job': g.last_job, 'end_reason': g.end_reason, 'end_time': g.end_time, 'mac': g.mac, 'events': g.events[-EVENT_MAX:], 'end_reported': g.session_end_reported, 'knocks': g.knocks, 'knock_since': g.knock_since, 'knock_time': g.knock_time}
    tmp = status_path() + '.new'
    try:
        with open(tmp, 'w') as f:
            json.dump(d, f, indent=1)
        os.chmod(tmp, 384)
        os.replace(tmp, status_path())
    except OSError as e:
        log('status.json not written: %s' % e)

def status_read():
    try:
        with open(status_path()) as f:
            d = legacy.normalize_in(json.load(f))
    except Exception:
        return
    with _lock:
        for k, v in d.items():
            if k.startswith('_') or not isinstance(v, dict):
                continue
            g = get_device(k)
            g.prev_seen = float(v.get('seen') or 0)
            g.last_ip = v.get('ip', '')
            g.sessions = int(v.get('sessions') or 0)
            g.running = None
            g.last_job = v.get('last_job')
            g.end_reason = v.get('end_reason', '')
            g.end_time = float(v.get('end_time') or 0)
            g.events = v.get('events', [])[-EVENT_MAX:]
            g.since_prev = float(v.get('since') or 0)
            g.old_state = 'silent'
            g.session_end_reported = True
            g.knocks = int(v.get('knocks') or 0)
            g.knock_since = float(v.get('knock_since') or 0)
            g.knock_time = float(v.get('knock_time') or 0)
            if v.get('mac') and (not g.mac):
                g.mac = v['mac']
            if g.prev_seen and now() - g.prev_seen < 600:
                event(g, 'SERVER RESTARTED; the device was last seen %d s ago (session tokens are gone, it must log in again)' % (now() - g.prev_seen))

def watchdog():
    last_backup = 0.0
    while True:
        time.sleep(WATCHDOG_S)
        try:
            changed = False
            with _lock:
                for g in list(_devices.values()):
                    z = state(g)
                    old = g.old_state
                    if z != old:
                        changed = True
                        g.old_state = z
                        silence = now() - g.seen if g.seen else 0
                        duration = g.seen - g.since if g.since and g.seen else 0
                        if z == 'busy':
                            event(g, 'BUSY: job %s %s running for %d s; the helper does not report during a command (up to 1200 s) -- not an outage' % (g.running.get('id'), g.running.get('kind'), now() - g.running.get('since', now())))
                        elif z == 'clean_exit':
                            g.end_reason = 'clean logout (bye)'
                            g.end_time = g.seen
                            g.session_end_reported = True
                            event(g, 'DISCONNECTED: clean logout after a %d s session' % duration)
                        elif z == 'silent':
                            extra = ''
                            if g.running:
                                extra = ' Job %s %s was unanswered for %d s -- the helper hung on the job or the device died meanwhile.' % (g.running.get('id'), g.running.get('kind'), now() - g.running.get('since', now()))
                            g.end_reason = 'silent: no report for %d s, no logout, no wire error' % silence + extra
                            g.end_time = g.seen
                            event(g, 'SILENT: last report %s, session lasted %d s, %d reports, longest gap %d s, IP %s, commit %s.%s The server cannot tell whether the device is off, crashed, suspended or the network is gone.' % (utc_text(g.seen), duration, g.polls, g.max_gap, g.last_ip or '?', (g.info or {}).get('commit', '') or '?', extra))
                        elif z == 'knocking':
                            event(g, 'ONLY KNOCKING: %d greetings since %s (about every 30 s), but never a `hello` after. The device IS ALIVE and reaches the server; login fails on the device itself before it can send anything signed (/bin/jsig cannot start, e.g. process table full, or work file not writable). Last real contact: %s.' % (g.knocks, utc_text(g.knock_since), utc_text(g.seen or g.prev_seen)))
                        elif z == 'online' and old in ('silent', 'busy', 'clean_exit', 'knocking'):
                            event(g, 'BACK (was %s)' % old)
                    if z in ('silent', 'clean_exit'):
                        drop_stale(g)
            if changed or now() - last_backup > 60:
                last_backup = now()
                status_write()
        except Exception as e:
            log('Watchdog error: %s' % e)

def why_text(g):
    z = state(g)
    t = g.seen or g.prev_seen
    ago = now() - t if t else None
    if z == 'never':
        return 'The device has never reported in.'
    if z == 'online':
        return 'online, session for %d s, last report %d s ago.' % (now() - g.since, ago)
    if z == 'busy':
        return 'working for %d s on job %s (%s); older helpers do not report meanwhile -- not offline, just quiet.' % (now() - g.running['since'], g.running['id'], g.running['kind'])
    if z == 'clean_exit':
        return 'logged out %d s ago with bye.' % ago
    if z == 'knocking':
        return 'ALIVE BUT CANNOT GET IN: since %s (%d greetings, about every 30 s) the device knocks but never sends `hello`. Login fails on the device (probably no free process slot for /bin/jsig). The device is still running: a power cycle fixes it, Wake-on-LAN does not.' % (utc_text(g.knock_since), g.knocks)
    if not g.seen:
        return 'not seen since the server start (%s); last contact before: %s (%d s ago).' % (utc_text(SERVER_START), utc_text(g.prev_seen), ago)
    return 'SILENT for %d s (last report %s). No logout word, no error, no server restart gap. Cause cannot be determined from the server side: device off / crashed / suspended / network gone. %s' % (ago, utc_text(t), 'Open job: %s %s.' % (g.running['id'], g.running['kind']) if g.running else '')

def why_json(g):
    t = g.seen or g.prev_seen
    return {'device_id': g.device_id, 'state': state(g), 'summary': why_text(g), 'last_contact_utc': utc_text(t), 'last_contact_vienna': vienna_text(t), 'ago_s': round(now() - t, 1) if t else None, 'ip': g.last_ip or (g.info or {}).get('ip_external'), 'ip_hint': 'ip is the address of the forwarder in the server rack (X-Von), not the home address of the device' if (g.last_ip or '').startswith('192.168.1.') else '', 'commit': (g.info or {}).get('commit', ''), 'sessions_since_status': g.sessions, 'session_duration_s': round(g.seen - g.since, 1) if g.since and g.seen else None, 'polls_in_session': g.polls, 'longest_gap_s': round(g.max_gap, 1), 'knocks': g.knocks, 'knocking_since_utc': utc_text(g.knock_since) if g.knock_since else None, 'last_knock_utc': utc_text(g.knock_time) if g.knock_time else None, 'running_job': g.running, 'last_job': g.last_job, 'open_jobs': len(g.jobs), 'end_reason': g.end_reason, 'mac': g.mac, 'server_start_utc': utc_text(SERVER_START), 'server_uptime_s': round(now() - SERVER_START), 'events': [[utc_text(e[0]), e[1]] for e in g.events[-25:]]}

def magic_packet(mac):
    h = re.sub('[^0-9a-fA-F]', '', mac)
    if len(h) != 12:
        raise ValueError('MAC must have 12 hex digits')
    b = bytes.fromhex(h)
    return b'\xff' * 6 + b * 16

def mac_normalize(mac):
    h = re.sub('[^0-9a-fA-F]', '', mac).lower()
    if len(h) != 12:
        raise ValueError('MAC must have 12 hex digits')
    return ':'.join((h[i:i + 2] for i in range(0, 12, 2)))

def wol_send(mac, targets, port=9):
    import socket
    packet = magic_packet(mac)
    sent = []
    for z in targets:
        for p in (port, 7):
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            try:
                s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
                s.sendto(packet, (z, p))
                sent.append('%s:%d' % (z, p))
            except OSError as e:
                sent.append('%s:%d ERROR %s' % (z, p, e))
            finally:
                s.close()
    return sent
SERVER_START = time.time()
_unknown = {}
_limiter = pairing.WrongCodeLimiter()

def get_device(device_id, create=True):
    with _lock:
        g = _devices.get(device_id)
        if g is None and create:
            g = Device(device_id)
            _devices[device_id] = g
        return g

def result_dir(device_id):
    p = os.path.join(_root, 'devices', sanitize(device_id))
    os.makedirs(p, exist_ok=True)
    return p

def book_write():
    with _lock:
        d = {}
        for k, g in _devices.items():
            if g.paired or g.blocked:
                d[k] = {'pubkey': g.pubkey, 'secret': g.secret, 'paired': g.paired, 'blocked': g.blocked, 'info': g.info, 'mac': g.mac}
    tmp = os.path.join(_root, 'pairing_book.json.new')
    with open(tmp, 'w') as f:
        json.dump(d, f, indent=1)
    os.chmod(tmp, 384)
    os.replace(tmp, os.path.join(_root, 'pairing_book.json'))

def book_read():
    p = os.path.join(_root, 'pairing_book.json')
    if not os.path.exists(p):
        return
    try:
        with open(p) as f:
            d = legacy.normalize_in(json.load(f))
    except Exception as e:
        log('pairing book unreadable: %s' % e)
        return
    with _lock:
        for k, v in d.items():
            g = get_device(k)
            g.pubkey = v.get('pubkey')
            g.secret = v.get('secret')
            g.paired = bool(v.get('paired'))
            g.blocked = bool(v.get('blocked'))
            g.info = v.get('info') or {}
            g.mac = v.get('mac', '') or ''
    log('Pairing book read: %d device(s)' % len(d))

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    dialect = legacy.CURRENT
    server_version = 'OrientBridge/1'

    def log_message(self, fmt, *args):
        pass

    def read_body(self, limit=MAX_BODY):
        try:
            n = int(self.headers.get('Content-Length') or 0)
        except ValueError:
            self.error(400, 'bad Content-Length')
            return None
        if n < 0 or n > limit:
            self.error(413, 'body too large')
            return None
        data = b''
        remaining = n
        while remaining > 0:
            state_row = self.rfile.read(min(remaining, 65536))
            if not state_row:
                break
            data += state_row
            remaining -= len(state_row)
        return data

    def hdr(self, name, default=''):
        return legacy.header(self.headers, name, default)

    def query(self):
        found = {}
        if '?' in self.path:
            for part in self.path.split('?', 1)[1].split('&'):
                if '=' in part:
                    k, v = part.split('=', 1)
                    found[k] = v
        return legacy.normalize_in(found)

    def read_json(self):
        raw = self.read_body(MAX_JOB_BODY)
        if raw is None:
            return None
        try:
            return legacy.normalize_in(json.loads(raw.decode('utf-8')))
        except Exception:
            self.error(400, 'bad json')
            return None

    def reply(self, obj, code=200):
        raw = json.dumps(self.dialect.out(obj)).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(raw)))
        self.end_headers()
        try:
            self.wfile.write(raw)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def error(self, code, text):
        self.reply({'error': text}, code)

    def client_ip(self):
        actual = self.client_address[0]
        if actual in ('127.0.0.1', '::1'):
            v = self.headers.get('X-Von')
            if v:
                return sanitize(v, 45)
        return actual

    def is_admin(self):
        expected = self.server.admin_key
        actual = self.hdr('X-Bridge-Admin')
        return bool(expected) and hmac.compare_digest(expected, actual)

    def do_GET(self):
        path, self.dialect = legacy.resolve_path(self.path.split('?')[0].rstrip('/'))
        if path == '/bridge/devices':
            if not self.is_admin():
                self.error(403, 'admin key missing')
                return
            with _lock:
                items = [g.to_json() for g in _devices.values()]
            self.reply({'devices': items})
            return
        if path == '/bridge/pending':
            if not self.is_admin():
                self.error(403, 'admin key missing')
                return
            with _lock:
                items = pairing.pending_json(_devices, now())
            self.reply({'pending': items})
            return
        if path == '/bridge/fetch':
            self.fetch()
            return
        if path == '/bridge/why':
            if not self.is_admin():
                self.error(403, 'admin key missing')
                return
            target = sanitize(self.query().get('device', ''))
            with _lock:
                items = [why_json(g) for k, g in _devices.items() if (not target or k == target) and (g.seen or g.prev_seen or g.events or g.knock_time)]
            self.reply({'devices': items})
            return
        if path == '/bridge/health':
            self.reply({'healthy': True, 'devices': len(_devices), 'ed25519': HAS_ED25519})
            return
        if path.startswith('/bridge/dl/'):
            self.dl(path)
            return
        self.error(404, 'no such path')

    def dl(self, path):
        parts = path.split('/')
        if len(parts) != 5:
            self.error(404, 'no such path')
            return
        token, name = (parts[3], parts[4])
        if len(token) < 32 or not all((c in '0123456789abcdef' for c in token)) or (not name) or name.startswith('.') or ('/' in name) or (not all((c.isalnum() or c in '._-' for c in name))):
            self.error(404, 'no such path')
            return
        file = os.path.join(_root, 'dl', token, name)
        if not os.path.isfile(file):
            self.error(404, 'no such path')
            return
        size = os.path.getsize(file)
        start = 0
        range_header = self.headers.get('Range', '')
        if range_header.startswith('bytes=') and range_header[6:].split('-')[0].isdigit():
            start = min(int(range_header[6:].split('-')[0]), size)
        log('DL %s/%s from %d (%d)' % (token[:8], name, start, size))
        self.send_response(206 if start else 200)
        self.send_header('Content-Type', 'application/octet-stream')
        self.send_header('Content-Length', str(size - start))
        if start:
            self.send_header('Content-Range', 'bytes %d-%d/%d' % (start, size - 1, size))
        self.end_headers()
        try:
            with open(file, 'rb') as fh:
                fh.seek(start)
                while True:
                    chunk = fh.read(65536)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def fetch(self):
        if not self.is_admin():
            self.error(403, 'admin key missing')
            return
        query = self.query()
        device_id = sanitize(query.get('device', ''))
        aid = sanitize(query.get('id', ''), 32)
        g = get_device(device_id, create=False)
        if g is None:
            self.error(404, 'no such device')
            return
        end_at = now() + WAIT_S
        with _lock:
            while aid not in g.results and now() < end_at:
                g.waker.wait(timeout=max(0.1, end_at - now()))
            pair = g.results.pop(aid, None)
        if pair is None:
            self.error(404, 'no result yet')
            return
        head, body = pair
        self.send_response(200)
        self.send_header('Content-Type', head.get('type', 'application/octet-stream'))
        self.send_header(self.dialect.header_name('X-Bridge-Status'), str(self.dialect.status(head.get('status', ''))))
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_POST(self):
        path, self.dialect = legacy.resolve_path(self.path.split('?')[0].rstrip('/'))
        if path == '/bridge/login':
            self.login()
        elif path == '/bridge/wait':
            self.wait()
        elif path == '/bridge/result':
            self.result()
        elif path == '/bridge/job':
            self.job()
        elif path == '/bridge/pair':
            self.pair()
        elif path == '/bridge/forget':
            self.forget()
        elif path == '/bridge/wire':
            self.wire()
        elif path == '/bridge/wol':
            self.wol()
        else:
            self.error(404, 'no such path')

    def login(self):
        d = self.read_json()
        if d is None:
            return
        device_id = sanitize(str(d.get('device_id', '')))
        if device_id == 'unknown':
            self.error(400, 'missing device id')
            return
        ip = self.client_ip()
        g = get_device(device_id)
        with _lock:
            if g.blocked:
                log('REJECTED (blocked): %s from %s' % (device_id, ip))
                self.error(403, 'this device is blocked')
                return
            pub = str(d.get('pubkey', ''))[:64]
            if not g.paired:
                if not g.code:
                    g.code = '%06d' % secrets.randbelow(1000000)
                g.pubkey = pub or g.pubkey
                g.info = self.info_from(d, ip)
                log('PAIRING NEEDED: %s (%s) code %s' % (device_id, ip, g.code))
                self.reply({'state': 'pairing-needed', 'code': g.code})
                return
            if g.pubkey and pub and (pub != g.pubkey):
                log('REJECTED (foreign key): %s from %s' % (device_id, ip))
                self.error(403, 'key does not match the pairing')
                return
            sig = str(d.get('signature', ''))
            challenge = str(d.get('challenge', ''))
            if not sig:
                g.challenge = secrets.token_hex(16)
                self.reply({'state': 'challenge', 'challenge': g.challenge})
                return
            expected_challenge = g.challenge
            if not expected_challenge or not hmac.compare_digest(expected_challenge, challenge):
                log('REJECTED (wrong challenge): %s' % device_id)
                self.error(403, 'challenge does not match')
                return
            g.challenge = None
            ok = signature_ok(g, device_id, challenge, sig)
            if ok is None:
                self.error(403, 'no shared secret agreed')
                return
            if not ok:
                log('REJECTED (bad signature): %s from %s' % (device_id, ip))
                self.error(403, 'signature invalid')
                return
            g.token = secrets.token_hex(24)
            g.token_until = now() + TOKEN_TTL_S
            session_begins(g, ip)
            g.seen = now()
            g.since = now()
            g.info = self.info_from(d, ip)
            log('LOGGED IN: %s (%s) %s' % (device_id, ip, g.info.get('hostname', '')))
            self.reply({'state': 'welcome', 'token': g.token, 'valid_s': TOKEN_TTL_S})

    def info_from(self, d, ip):
        i = d.get('info') or {}
        return {'hostname': str(i.get('hostname', ''))[:64], 'commit': str(i.get('commit', ''))[:40], 'resolution': str(i.get('resolution', ''))[:24], 'ip_internal': str(i.get('ip', ''))[:40], 'ip_external': ip, 'uptime_s': i.get('uptime_s')}

    def check_token(self, d):
        device_id = sanitize(str(d.get('device_id', '')))
        token = str(d.get('token', ''))
        g = get_device(device_id, create=False)
        if g is None or not g.paired or g.blocked:
            self.error(403, 'not paired')
            return None
        if not g.token or not hmac.compare_digest(g.token, token):
            self.error(403, 'token invalid')
            return None
        if now() > g.token_until:
            self.error(403, 'token expired')
            return None
        g.seen = now()
        return g

    def wait(self):
        d = self.read_json()
        if d is None:
            return
        with _lock:
            g = self.check_token(d)
            if g is None:
                return
            end_at = now() + WAIT_S
            poll_seen(g)
            drop_stale(g)
            while not g.jobs and now() < end_at:
                g.waker.wait(timeout=max(0.1, end_at - now()))
                g.seen = now()
            if g.jobs:
                a = g.jobs.pop(0)
                job_dispatched(g, a)
                log('JOB -> %s: %s %s' % (g.device_id, a.get('kind'), a.get('target', '')))
                self.reply({'job': a})
            else:
                self.reply({'job': None})

    def result(self):
        device_id = sanitize(self.hdr('X-Bridge-Device'))
        token = self.hdr('X-Bridge-Token')
        aid = sanitize(self.hdr('X-Bridge-Id'), 32)
        status = legacy.result_status_in(self.hdr('X-Bridge-Status', 'ok'))[:64]
        mime = self.hdr('X-Bridge-Type', 'application/octet-stream')[:64]
        g = get_device(device_id, create=False)
        if g is None or not g.paired or g.blocked or (not g.token) or (not hmac.compare_digest(g.token, token)):
            self.error(403, 'token invalid')
            return
        raw = self.read_body()
        if raw is None:
            return
        with _lock:
            g.seen = now()
            g.results[aid] = ({'status': status, 'type': mime}, raw)
            job_done(g, aid, status)
            g.waker.notify_all()
        ext = '.png' if 'png' in mime else '.txt' if 'text' in mime else '.bin'
        folder = result_dir(device_id)
        name = '%s-%s%s' % (datetime.datetime.now().strftime('%H%M%S'), aid or 'none', ext)
        target = os.path.join(folder, name)
        try:
            with open(target, 'wb') as f:
                f.write(raw)
            files = sorted(os.listdir(folder))
            for old in files[:-KEEP_RESULTS]:
                try:
                    os.remove(os.path.join(folder, old))
                except OSError:
                    pass
        except OSError as e:
            log('Storing the result failed: %s' % e)
        log('RESULT <- %s: id=%s status=%s %d bytes -> %s' % (device_id, aid, status, len(raw), target))
        self.reply({'accepted': True, 'bytes': len(raw), 'stored_at': target})

    def job(self):
        if not self.is_admin():
            self.error(403, 'admin key missing')
            return
        d = self.read_json()
        if d is None:
            return
        device_id = sanitize(str(d.get('device', '')))
        g = get_device(device_id, create=False)
        if g is None:
            self.error(404, 'no such device')
            return
        kind = str(d.get('kind', ''))[:24]
        kind = legacy.kind_in(kind)
        if kind not in JOB_KINDS:
            self.error(400, 'unknown job kind')
            return
        with _lock:
            g.counter += 1
            aid = '%d' % g.counter
            a = {'id': aid, 'kind': kind, 'ts': now(), 'target': str(d.get('target', ''))[:512], 'value': str(d.get('value', ''))[:MAX_VALUE]}
            if 'ttl_s' in d:
                try:
                    a['ttl_s'] = max(0, int(d['ttl_s']))
                except (TypeError, ValueError):
                    pass
            g.jobs.append(a)
            g.waker.notify_all()
        self.reply({'id': aid, 'queued': True, 'connected': g.alive()})

    def wol(self):
        if not self.is_admin():
            self.error(403, 'admin key missing')
            return
        d = self.read_json()
        if d is None:
            return
        mac = str(d.get('mac', ''))
        device_id = sanitize(str(d.get('device', '')))
        g = get_device(device_id, create=False) if device_id else None
        if g is not None and (not mac):
            mac = g.mac
        try:
            magic_packet(mac)
        except ValueError:
            self.error(400, 'invalid MAC (pass one or store it first)')
            return
        targets = d.get('broadcast') or ['255.255.255.255']
        if isinstance(targets, str):
            targets = [targets]
        targets = [str(z)[:40] for z in targets][:8]
        if g is not None and d.get('save'):
            with _lock:
                g.mac = mac_normalize(mac)
                book_write()
        out = wol_send(mac, targets)
        if g is not None:
            event(g, 'WOL sent to %s (MAC %s)' % (', '.join(targets), mac))
        self.reply({'sent': out, 'mac': mac, 'hint': 'The packet leaves the server. It only wakes devices in the same broadcast network.'})

    def pair(self):
        if not self.is_admin():
            self.error(403, 'admin key missing')
            return
        d = self.read_json()
        if d is None:
            return
        if str(d.get('what', '')) == 'preauth':
            pub = str(d.get('pubkey', '')).lower()
            if len(pub) != 64 or any((c not in '0123456789abcdef' for c in pub)):
                self.error(400, 'pubkey must be 64 hex digits')
                return
            device_id = 'osum-' + pub[:12]
            g = get_device(device_id)
            with _lock:
                g.pubkey = pub
                g.paired = True
                g.blocked = False
                g.code = None
                book_write()
            log('PRE-PAIRED: %s' % device_id)
            self.reply({'paired': True, 'device_id': device_id})
            return
        if 'device' not in d and 'code' in d:
            self.pair_by_code(d)
            return
        device_id = sanitize(str(d.get('device', '')))
        g = get_device(device_id, create=False)
        if g is None:
            self.error(404, 'no such device')
            return
        what = str(d.get('what', 'approve'))
        if what == 'mac':
            try:
                magic_packet(str(d.get('mac', '')))
            except ValueError:
                self.error(400, 'invalid MAC')
                return
            with _lock:
                g.mac = mac_normalize(str(d.get('mac')))
                book_write()
            log('MAC set: %s = %s' % (device_id, g.mac))
            self.reply({'mac': g.mac})
            return
        with _lock:
            if what == 'block':
                g.blocked = True
                g.paired = False
                g.token = None
                log('BLOCKED: %s' % device_id)
                book_write()
                self.reply({'blocked': True})
                return
            code = str(d.get('code', ''))
            if not pairing.code_valid(g, now()) or not hmac.compare_digest(g.code, code):
                log('PAIRING REJECTED (wrong code): %s' % device_id)
                self.error(403, 'code does not match')
                return
            g.paired = True
            g.blocked = False
            g.code = None
            if not HAS_ED25519 and (not g.secret):
                g.secret = secrets.token_hex(32)
            book_write()
            log('PAIRED: %s' % device_id)
            self.reply({'paired': True, 'secret': g.secret})

    def pair_by_code(self, d):
        code = str(d.get('code', ''))[:16]
        t = now()
        with _lock:
            if _limiter.locked(t):
                self.error(429, 'too many wrong codes, try again later')
                return
            g = pairing.find_by_code(_devices, code, t)
            if g is None:
                if _limiter.record_wrong(t):
                    pairing.reroll_all(_devices, t)
                    log('PAIRING LOCKED: too many wrong codes, pending codes re-rolled')
                else:
                    log('PAIRING REJECTED (no match)')
                self.error(404, 'no match')
                return
            if d.get('peek'):
                self.reply({'found': True, 'id': g.device_id, 'info': g.info})
                return
            g.paired = True
            g.blocked = False
            g.code = None
            _limiter.clear()
            if not HAS_ED25519 and (not g.secret):
                g.secret = secrets.token_hex(32)
            book_write()
            log('PAIRED (code): %s' % g.device_id)
            self.reply({'paired': True, 'id': g.device_id, 'info': g.info})

    def forget(self):
        if not self.is_admin():
            self.error(403, 'admin key missing')
            return
        d = self.read_json()
        if d is None:
            return
        device_id = sanitize(str(d.get('device', '')))
        g = get_device(device_id, create=False)
        if g is None:
            self.error(404, 'no such device')
            return
        with _lock:
            pairing.forget_device(g)
            g.waker.notify_all()
            book_write()
        log('FORGOTTEN: %s' % device_id)
        self.reply({'ok': True})

    def wire(self):
        raw = self.read_body(MAX_JOB_BODY)
        if raw is None:
            return
        wire_id = sanitize(self.hdr('X-Bridge-Wire'), 64)
        if not self.hdr('X-Bridge-Wire'):
            t = now()
            if t - _unknown.get('(no X-Bridge-Wire)', 0) > 600:
                _unknown['(no X-Bridge-Wire)'] = t
                log('WARNING: request without X-Bridge-Wire -- the forwarder does not pass the header on; all devices would share ONE wire state')
        if not wire_id:
            self.error(400, 'no X-Bridge-Wire')
            return
        ip = self.client_ip()
        first_word = legacy.wire_word_in(raw.split(b' ', 1)[0].split(b'\n', 1)[0].decode('utf-8', 'replace'))
        if first_word == 'osum-bridge' and len(wire_id) >= 12:
            known = get_device('osum-' + wire_id[:12], create=False)
            if known is not None and known.paired and (not known.blocked):
                with _lock:
                    if not known.knock_time or known.knock_time <= known.hello_time:
                        known.knocks = 0
                        known.knock_since = now()
                    known.knocks += 1
                    known.knock_time = now()
                    known.last_ip = known.last_ip or ip
            else:
                t = now()
                if t - _unknown.get(wire_id, 0) > 300:
                    _unknown[wire_id] = t
                    log('GREETING from unknown/unpaired wire id %s (%s)' % (wire_id, ip))
        elif first_word == 'hello':
            known = get_device('osum-' + wire_id[:12], create=False)
            if known is not None:
                with _lock:
                    known.hello_time = now()
        with _lock:
            for k in [k for k, v in self.server.wires.items() if now() - v.get('seen', 0) > WIRE_DEAD_S]:
                del self.server.wires[k]
            state_row = self.server.wires.setdefault(wire_id, {'device_id': None, 'pub': None})
            state_row['seen'] = now()
        out_bytes = self._wire_step(state_row, raw, ip)
        self.send_response(200)
        self.send_header('Content-Type', 'application/octet-stream')
        self.send_header('Content-Length', str(len(out_bytes)))
        self.end_headers()
        try:
            self.wfile.write(out_bytes)
        except (BrokenPipeError, ConnectionResetError):
            pass

    @staticmethod
    def _split_line(raw):
        i = raw.find(b'\n')
        if i < 0:
            return ([], b'')
        f = raw[:i].decode('utf-8', 'replace').strip().split()
        n = int(f[-1]) if f and f[-1].isdigit() else 0
        return (f, raw[i + 1:i + 1 + n])

    def _send(self, head, payload=b''):
        return (self.dialect.word(head) + ' ' + str(len(payload))).encode() + b'\n' + payload

    def _drop(self, reason):
        return self._send('drop ' + reason.encode().hex())

    def _wire_step(self, state_row, raw, ip):
        f, payload = self._split_line(raw)
        if not f:
            return self._drop('empty line')
        word = legacy.wire_word_in(f[0])
        if word == 'osum-bridge':
            return b''
        if word == 'hello':
            pub = (f[1] if len(f) > 1 else '')[:64]
            device_id = 'osum-' + pub[:12]
            state_row['device_id'] = device_id
            state_row['pub'] = pub
            g = get_device(device_id)
            with _lock:
                if g.blocked:
                    log('REJECTED (blocked): %s from %s' % (device_id, ip))
                    return self._drop('this device is blocked')
                if not g.paired:
                    g.pubkey = pub or g.pubkey
                    g.info = self.info_from({'info': {'ip': ip}}, ip)
                    pairing.ensure_code(_devices, g, now())
                    book_write()
                    log('PAIRING NEEDED: %s (%s)' % (device_id, ip))
                    return self._send('pairing-needed ' + g.code.encode().hex())
                if g.pubkey and pub and (pub != g.pubkey):
                    log('REJECTED (foreign key): %s from %s' % (device_id, ip))
                    return self._drop('key does not match the pairing')
                g.challenge = secrets.token_hex(16)
                return self._send('challenge ' + g.challenge)
        device_id = state_row.get('device_id')
        if not device_id:
            return self._drop('no handshake')
        g = get_device(device_id, create=False)
        if g is None:
            return self._drop('unknown device')
        if word == 'proof':
            sig = (f[1] if len(f) > 1 else '')[:128]
            with _lock:
                challenge = g.challenge
                if not challenge:
                    return self._drop('no challenge open')
                g.challenge = None
                ok = signature_ok(g, device_id, challenge, sig)
                if ok is None:
                    return self._drop('no shared secret agreed')
                if not ok:
                    log('REJECTED (bad signature): %s from %s' % (device_id, ip))
                    return self._drop('signature invalid')
                g.token = secrets.token_hex(24)
                g.token_until = now() + TOKEN_TTL_S
                session_begins(g, ip)
                g.seen = now()
                g.since = now()
                g.info = self.info_from({'info': {'ip': ip}}, ip)
                book_write()
            log('LOGGED IN (wire): %s (%s)' % (device_id, ip))
            return self._send('welcome')
        if not g.token or g.token_until < now():
            event(g, 'sent drop: session token missing or expired (server restarted or 12 h over); the helper must log in again', loud=False)
            return self._drop('not logged in')
        if word == 'alive':
            with _lock:
                g.seen = now()
            return b''
        if word == 'info':
            try:
                kv = dict((x.split('=', 1) for x in payload.decode('utf-8', 'replace').split(';') if '=' in x))
            except Exception:
                kv = {}
            with _lock:
                g.seen = now()
                m = kv.get('mac', '')
                try:
                    m = mac_normalize(m)
                    if g.mac != m:
                        g.mac = m
                        book_write()
                        event(g, 'MAC reported: %s' % g.mac)
                except ValueError:
                    pass
                if kv.get('commit'):
                    g.info['commit'] = kv['commit'][:40]
            return b''
        if word == 'poll':
            poll_seen(g)
            with _lock:
                drop_stale(g)
                job_item = g.jobs.pop(0) if g.jobs else None
                if job_item is not None:
                    job_dispatched(g, job_item)
            if job_item is None:
                return b''
            kind = job_item.get('kind', '')
            payload = b''
            if kind == 'write':
                content = job_item.get('target', '') or ''
                w = job_item.get('value', '') or ''
                if w.startswith('b64:'):
                    try:
                        payload = base64.b64decode(w[4:])
                    except Exception:
                        payload = b''
                else:
                    payload = w.encode()
            elif kind in ('input',) + legacy.INPUT_KINDS:
                content = job_item.get('value', '') or job_item.get('target', '')
            else:
                content = job_item.get('target', '') or job_item.get('value', '') or ''
            wire_kind, content = self.dialect.wire_kind(kind, content)
            a1 = content.encode().hex() if content else '0'
            log('JOB -> %s: id=%s kind=%s' % (device_id, job_item.get('id', 0), wire_kind))
            return self._send('job %s %s %s 0' % (job_item.get('id', 0), wire_kind, a1), payload)
        if word == 'done':
            aid = sanitize(f[1] if len(f) > 1 else '0', 32)
            status = legacy.result_status_in((f[2] if len(f) > 2 else 'ok')[:64])
            mime = 'image/png' if payload[:8] == b'\x89PNG\r\n\x1a\n' else 'text/plain; charset=utf-8'
            with _lock:
                g.seen = now()
                g.results[aid] = ({'status': status, 'type': mime}, payload)
                job_done(g, aid, status)
                g.waker.notify_all()
            ext = '.png' if 'png' in mime else '.txt'
            folder = result_dir(device_id)
            name = '%s-%s%s' % (datetime.datetime.now().strftime('%H%M%S'), aid or 'none', ext)
            target = os.path.join(folder, name)
            try:
                with open(target, 'wb') as fh:
                    fh.write(payload)
                files = sorted(os.listdir(folder))
                for old_name in files[:-KEEP_RESULTS]:
                    try:
                        os.remove(os.path.join(folder, old_name))
                    except OSError:
                        pass
            except OSError as e:
                log('Storing the result failed: %s' % e)
            log('RESULT <- %s: id=%s status=%s %d bytes -> %s' % (device_id, aid, status, len(payload), target))
            return b''
        if word == 'bye':
            with _lock:
                g.seen = now()
                g.bye = True
            return b''
        return self._drop('unknown: ' + word)

class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True
    admin_key = None
    wires = {}

def main():
    global _root
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', type=int, default=8090)
    ap.add_argument('--bind', default='127.0.0.1')
    ap.add_argument('--root', *legacy.ARG_ALIASES, dest='root', default='/srv/bruecke')
    a = ap.parse_args()
    _root = a.root
    legacy.adopt_legacy_state(_root)
    os.makedirs(os.path.join(_root, 'devices'), exist_ok=True)
    path = os.path.join(_root, 'admin.key')
    if not os.path.exists(path):
        with open(path, 'w') as f:
            f.write(secrets.token_hex(32))
        os.chmod(path, 384)
    with open(path) as f:
        Server.admin_key = f.read().strip()
    book_read()
    status_read()
    threading.Thread(target=watchdog, daemon=True).start()
    with Server((a.bind, a.port), Handler) as s:
        log('Bridge listening on %s:%d (root %s, Ed25519 %s)' % (a.bind, a.port, _root, 'yes' if HAS_ED25519 else 'no -- HMAC fallback'))
        s.serve_forever()
if __name__ == '__main__':
    main()
