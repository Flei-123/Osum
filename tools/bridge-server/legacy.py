import os
import shutil

LEGACY_PREFIX = "/bruecke/"
CURRENT_PREFIX = "/bridge/"

PATHS = {
    "anmelden": "login",
    "warten": "wait",
    "ergebnis": "result",
    "geraete": "devices",
    "auftrag": "job",
    "holen": "fetch",
    "koppeln": "pair",
    "draht": "wire",
    "warum": "why",
    "gesund": "health",
    "dl": "dl",
    "wol": "wol",
}

HEADERS = {
    "X-Bridge-Admin": "X-Bruecke-Verwalter",
    "X-Bridge-Wire": "X-Draht",
    "X-Bridge-Device": "X-Bruecke-Geraet",
    "X-Bridge-Token": "X-Bruecke-Marke",
    "X-Bridge-Id": "X-Bruecke-Id",
    "X-Bridge-Status": "X-Bruecke-Status",
    "X-Bridge-Type": "X-Bruecke-Typ",
}

KEYS_DE_EN = {
    "kennung": "device_id", "geraet": "device", "geraete": "devices", "unterschrift": "signature",
    "forderung": "challenge", "marke": "token", "gueltig_s": "valid_s", "zustand": "state",
    "rechner": "hostname", "aufloesung": "resolution", "ip_intern": "ip_internal", "ip_extern": "ip_external",
    "laufzeit_s": "uptime_s", "gekoppelt": "paired", "gesperrt": "blocked", "verbunden": "connected",
    "zuletzt_gesehen_s": "last_seen_s", "verbunden_seit_s": "connected_since_s", "offene_auftraege": "open_jobs",
    "letzter_kontakt_utc": "last_contact_utc", "letzter_kontakt_wien": "last_contact_vienna",
    "auftrag": "job", "art": "kind", "ziel": "target", "wert": "value", "eingereiht": "queued",
    "angenommen": "accepted", "oktette": "bytes", "ablage": "stored_at", "geheim": "secret", "was": "what",
    "fehler": "error", "gesund": "healthy", "hinweis": "hint", "gesendet": "sent", "speichern": "save",
    "kurz": "summary", "vor_s": "ago_s", "ip_hinweis": "ip_hint", "sitzungen_seit_status": "sessions_since_status",
    "sitzung_dauer_s": "session_duration_s", "meldungen_in_sitzung": "polls_in_session",
    "laengste_luecke_s": "longest_gap_s", "klopfen": "knocks", "klopft_seit_utc": "knocking_since_utc",
    "letztes_klopfen_utc": "last_knock_utc", "laufender_auftrag": "running_job", "letzter_auftrag": "last_job",
    "ende_grund": "end_reason", "server_laeuft_s": "server_uptime_s", "ereignisse": "events",
    "gesehen": "seen", "seit": "since", "sitzungen": "sessions", "pulse": "polls", "max_luecke": "max_gap",
    "tschuess": "bye", "laufend": "running", "ende_zeit": "end_time", "ende_gemeldet": "end_reported",
    "klopf_seit": "knock_since", "klopf_zeit": "knock_time", "von": "from", "bis": "until", "typ": "type",
}
KEYS_EN_DE = {v: k for k, v in KEYS_DE_EN.items()}

KINDS_DE_EN = {
    "befehl": "run", "lies": "read", "schreib": "write", "liste": "list", "foto": "screenshot",
    "eingabe": "input", "taste": "key", "maus": "mouse", "knopf": "click", "protokoll": "log",
    "command": "run", "photo": "screenshot",
}
KINDS_EN_DE = {"run": "befehl", "read": "lies", "write": "schreib", "list": "liste", "screenshot": "foto",
               "input": "eingabe", "key": "taste", "mouse": "maus", "click": "knopf", "log": "protokoll"}

STATE_VALUES_DE_EN = {
    "kopplung-noetig": "pairing-needed", "forderung": "challenge", "willkommen": "welcome",
    "nie": "never", "beschaeftigt": "busy", "sauber_beendet": "clean_exit", "stumm": "silent",
    "klopft": "knocking", "laeuft": "running",
}
STATE_VALUES_EN_DE = {v: k for k, v in STATE_VALUES_DE_EN.items()}

WIRE_WORDS_DE_EN = {
    "osum-bruecke": "osum-bridge", "ich": "hello", "kopplung-noetig": "pairing-needed", "kopplung": "pair",
    "kopplung-abgelehnt": "pair-rejected", "frage": "challenge", "beweis": "proof", "willkommen": "welcome",
    "weg": "drop", "lebt": "alive", "puls": "poll", "auftrag": "job", "fertig": "done", "tschuess": "bye",
}
WIRE_WORDS_EN_DE = {v: k for k, v in WIRE_WORDS_DE_EN.items()}
RESULT_STATUS_DE_EN = {"nein": "failed"}
SIGN_PREFIXES = ("bridge:", "bruecke:")
INPUT_KINDS = ("key", "mouse", "click", "scan")

STATE_FILES = {"pairing_book.json": "koppelbuch.json", "admin.key": "verwalter.key"}
STATE_DIRS = {"devices": "geraete"}
ARG_ALIASES = ("--wurzel",)
ENV_RENAMES = {"BRIDGE_DEAD_S": "BRUECKE_TOT_S", "BRIDGE_WATCHDOG_S": "BRUECKE_WAECHTER_S"}


def _rename_keys(obj, table, value_keys):
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            nk = table.get(k, k) if isinstance(k, str) else k
            v = _rename_keys(v, table, value_keys)
            if isinstance(v, str) and nk in value_keys:
                v = value_keys[nk].get(v, v)
            out[nk] = v
        return out
    if isinstance(obj, list):
        return [_rename_keys(x, table, value_keys) for x in obj]
    return obj


def normalize_in(obj):
    return _rename_keys(obj, KEYS_DE_EN, {"kind": KINDS_DE_EN, "state": STATE_VALUES_DE_EN})


def kind_in(kind):
    return KINDS_DE_EN.get(kind, kind)


def wire_word_in(word):
    return WIRE_WORDS_DE_EN.get(word, word)


def result_status_in(status):
    return RESULT_STATUS_DE_EN.get(status, status)


def resolve_path(raw):
    if raw.startswith(LEGACY_PREFIX):
        rest = raw[len(LEGACY_PREFIX):]
        head, sep, tail = rest.partition("/")
        return CURRENT_PREFIX + PATHS.get(head, head) + sep + tail, LEGACY
    return raw, CURRENT


def header(headers, name, default=""):
    value = headers.get(name)
    if value is None:
        old = HEADERS.get(name)
        value = headers.get(old) if old else None
    return default if value is None else value


def env(name, default):
    for candidate in (name, ENV_RENAMES.get(name), name.replace("BRIDGE_", "BRUECKE_", 1)):
        if candidate and candidate in os.environ:
            return os.environ[candidate]
    return default


class Dialect:
    legacy = False

    def out(self, obj):
        return obj

    def word(self, line):
        return line

    def header_name(self, name):
        return name

    def status(self, status):
        return status

    def wire_kind(self, kind, value):
        if kind in INPUT_KINDS:
            return "input", kind + " " + value
        return kind, value


class LegacyDialect(Dialect):
    legacy = True

    def out(self, obj):
        return _rename_keys(obj, KEYS_EN_DE, {"zustand": STATE_VALUES_EN_DE, "art": KINDS_EN_DE})

    def word(self, line):
        head, sep, tail = line.partition(" ")
        return WIRE_WORDS_EN_DE.get(head, head) + sep + tail

    def header_name(self, name):
        return HEADERS.get(name, name)

    def status(self, status):
        return {"failed": "nein"}.get(status, status)

    def wire_kind(self, kind, value):
        if kind in INPUT_KINDS:
            return "eingabe", KINDS_EN_DE.get(kind, kind) + " " + value
        return KINDS_EN_DE.get(kind, kind), value


CURRENT = Dialect()
LEGACY = LegacyDialect()


def adopt_legacy_state(root):
    for new, old in STATE_FILES.items():
        new_path, old_path = os.path.join(root, new), os.path.join(root, old)
        if not os.path.exists(new_path) and os.path.exists(old_path):
            shutil.copy2(old_path, new_path)
    for new, old in STATE_DIRS.items():
        new_path, old_path = os.path.join(root, new), os.path.join(root, old)
        if os.path.isdir(old_path) and not os.path.islink(old_path) and not os.path.exists(new_path):
            os.rename(old_path, new_path)
        if os.path.isdir(new_path) and not os.path.lexists(old_path):
            os.symlink(new, old_path)
