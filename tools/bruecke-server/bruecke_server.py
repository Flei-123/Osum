#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""bruecke/bruecke_server.py -- RUNDE BRUECKE.

Das Gegenstueck zu `kernel/app/bruecke.fi` in Osum: die Stelle, an der
Justins OrientOS-Rechner sich MELDET, und aus der JARVIS ihn bedienen
kann. Aufgebaut wie `orientstore/werkzeug/diagnose_server.py` -- ein
`http.server`, der genau die Pfade kennt, die er kennen muss, und sonst
nichts.

====================================================================
DIE RANDBEDINGUNG, aus der die ganze Bauform folgt
====================================================================

Justins Rechner steht NICHT im Netz des JARVIS-Servers. Beide haben
192.168.1.x, aber das sind zwei getrennte Heimnetze hinter NAT. Der
Server kann das Geraet NIE anrufen. Also ruft das Geraet den Server,
und zwar ueber den Weg, der auch aus fremden Netzen (Hotel, Handy,
Schule) hinausgeht: HTTPS auf Port 443 zu store.fleitec.com. Genau der
Weg, auf dem Certus seine Absturzberichte schickt -- der ist gemessen
und funktioniert.

WARUM LANGES POLLING UND KEIN DAUERPROTOKOLL. Der Prozess am Netz ist
in Osum `bruecke.fi`, und der soll so wenig koennen muessen wie
moeglich. Langes Polling braucht dort NUR das, was `fetch.fi` schon
kann: eine HTTPS-Anfrage stellen, eine Antwort lesen. Kein
HTTP-Upgrade, keine RFC-6455-Rahmen, keine Maskierung, kein zweiter
Zustandsautomat. Der Server haelt die Anfrage bis zu WARTE_S offen; ist
ein Auftrag da, antwortet er sofort. Damit ist die Verzoegerung bei
anliegender Arbeit dieselbe wie bei einem offenen Kanal, aber der Code
auf dem Geraet ist eine Schleife aus zwei Aufrufen.

====================================================================
DIE PFADE
====================================================================

  POST /bruecke/anmelden    Geraet meldet sich: Kennung, Schluessel,
                            Rechnername, Aufloesung, Abbild-Commit.
                            Antwort: Sitzungsmarke oder Kopplungscode.
  POST /bruecke/warten      LANGES POLLING. Geraet fragt nach Arbeit.
                            Antwort: ein Auftrag als JSON, oder nach
                            WARTE_S ein leeres `{"auftrag":null}`.
  POST /bruecke/ergebnis    Geraet liefert das Ergebnis eines Auftrags.
                            Rumpf ist roh (Bild, Datei, Ausgabe).
  GET  /bruecke/geraete     Wer ist da (fuer JARVIS/Cockpit).
  POST /bruecke/auftrag     JARVIS legt einen Auftrag in die Schlange.
  GET  /bruecke/holen       JARVIS holt ein Ergebnis ab.
  POST /bruecke/koppeln     Kopplung freigeben oder Geraet sperren.

WAS BEWUSST NICHT DRIN IST:
  * KEIN Pfad aus der Anfrage wird je zu einem Dateipfad. Ablagenamen
    bildet der Server aus Kennung, Datum und Zaehler.
  * KEINE Ausfuehrung hier. Dieser Dienst ist eine Schlange und ein
    Briefkasten; ausgefuehrt wird auf dem Geraet, nach dessen eigener
    Rechteliste (/etc/jarvis/rechte.conf).
  * OBERGRENZEN ueberall, sonst ist ein offener Endpunkt eine
    Einladung, die Platte zu fuellen.

Aufruf: python3 bruecke_server.py [--port 8089] [--wurzel /srv/bruecke]
"""
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

MAX_RUMPF = 24 * 1024 * 1024       # 24 MiB: ein Vollbild-PNG bei 3440x1440
# a `schreib` job carries its file content in "wert" (b64: for binary);
# jarvisd takes at most 1 MiB of payload (MAXNUTZ).
MAX_WERT = 1500000
JOB_KINDS_EN = {"befehl": "command", "lies": "read", "schreib": "write", "liste": "list",
                "foto": "photo", "eingabe": "input"}
JOB_KINDS_DE = {v: k for k, v in JOB_KINDS_EN.items()}
MAX_AUFTRAG = 2100 * 1024          # a job is text; a `schreib` job carries up to ~1.5 MB
WARTE_S = 25.0                     # so lange haelt ein `warten` still
MARKE_S = 12 * 3600                # Sitzungsmarke gilt zwoelf Stunden
TOT_S = 90                         # danach gilt ein Geraet als weg
BEHALTEN = 300                     # Ergebnisse je Geraet auf der Platte
DRAHT_TOT = 300                    # ein stiller Draht faellt nach 5 min weg
# 05.10.2026 (why-offline round). Env overrides exist for the tests only.
TOT_S = int(os.environ.get("BRUECKE_TOT_S", TOT_S))
JOB_TTL_S = int(os.environ.get("BRUECKE_JOB_TTL_S", 900))   # a queued job older than this is dropped
BUSY_GRACE_S = int(os.environ.get("BRUECKE_BUSY_GRACE_S", 1320))  # command_timeout 1200 s + slack
WAECHTER_S = float(os.environ.get("BRUECKE_WAECHTER_S", 5))
EREIGNIS_MAX = 80
STATUS_NAME = "status.json"

_sperre = threading.RLock()
_geraete = {}                      # kennung -> Geraet
_wurzel = "/srv/bruecke"


def sauber(s, grenze=64):
    """Nur Buchstaben, Ziffern, Punkt, Strich. Positiv ausgewaehlt.

    Die einzige Stelle, an der Text von aussen in einen Dateinamen
    geraet. Deshalb wird hier nicht gefiltert, sondern ausgewaehlt.
    """
    s = re.sub(r"[^A-Za-z0-9._-]", "", s or "")
    s = s.strip(".-") or "unbekannt"
    return s[:grenze]


def jetzt():
    return time.time()


def stempel():
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def melde(text):
    sys.stderr.write("[bruecke] %s %s\n" % (stempel(), text))
    sys.stderr.flush()


# ====================================================================
# DIE SCHLUESSEL
# ====================================================================
#
# Ein Geraet weist sich mit einem Ed25519-Schluesselpaar aus, das beim
# ersten Start AUF DEM GERAET entsteht; der private Teil verlaesst es
# nie. Der Server kennt nur den oeffentlichen Teil, und zwar erst,
# nachdem ein Mensch die Kopplung freigegeben hat.
#
# WARUM DIE FREIGABE NOETIG IST: ohne sie koennte jeder, der die Adresse
# kennt, ein Geraet anmelden. Der Code steht auf dem BILDSCHIRM des
# Geraets und muss ueber einen zweiten Weg (Justin sagt ihn mir)
# bestaetigt werden. Das ist dasselbe Muster wie bei `jarvisctl
# koppeln`.
#
# Ed25519 wird mit `cryptography` geprueft, wenn vorhanden. Fehlt die
# Bibliothek, faellt der Dienst auf HMAC-SHA256 ueber ein beim Koppeln
# vereinbartes Geheimnis zurueck -- das ist schwaecher (kein
# oeffentlicher Schluessel), aber immer noch beidseitig authentifiziert
# und NIEMALS ungeprueft. Welcher Weg gilt, steht im Protokoll.
try:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import (
        Ed25519PublicKey)
    from cryptography.exceptions import InvalidSignature
    HAT_ED25519 = True
except Exception:                                    # pragma: no cover
    HAT_ED25519 = False


def pruefe_unterschrift(pubkey_hex, nachricht, sig_hex):
    """Beweist das Geraet, dass es den privaten Schluessel hat?

    Rueckgabe True/False, oder None wenn es kein Ed25519 gibt -- dann
    nimmt der Aufrufer den HMAC-Weg. None heisst NIE "in Ordnung".
    """
    if not HAT_ED25519:
        return None
    try:
        roh = bytes.fromhex(pubkey_hex or "")
        sig = bytes.fromhex(sig_hex or "")
    except ValueError:
        return False
    if len(roh) != 32 or len(sig) != 64:
        return False
    try:
        Ed25519PublicKey.from_public_bytes(roh).verify(sig, nachricht)
        return True
    except InvalidSignature:
        return False
    except Exception:
        return False


class Geraet:
    """Ein OrientOS-Rechner, so wie der Server ihn sieht."""

    def __init__(self, kennung):
        self.kennung = kennung
        self.pubkey = None          # hex, erst nach Kopplung
        self.geheim = None          # HMAC-Rueckfallweg
        self.gekoppelt = False
        self.gesperrt = False
        self.code = None            # Kopplungscode, solange offen
        self.forderung = None       # Zufallsforderung, gilt genau einmal
        self.marke = None           # Sitzungsmarke
        self.marke_bis = 0.0
        self.gesehen = 0.0
        self.seit = 0.0             # seit wann verbunden
        self.info = {}              # Rechnername, Aufloesung, Commit, IP
        self.auftraege = []         # was noch zu tun ist
        self.ergebnisse = {}        # id -> (kopf, rumpf)
        self.zaehler = 0
        self.wecker = threading.Condition(_sperre)
        # why-offline bookkeeping (05.10.2026)
        self.mac = ""               # for Wake-on-LAN; set by the admin or reported by the device
        self.letzte_ip = ""
        self.sitzungen = 0          # sign-ins since the status file exists
        self.pulse = 0              # polls in the current session
        self.max_luecke = 0.0       # longest silence between two polls in the session
        self.tschuess = False       # session ended with a goodbye
        self.laufend = None         # job handed out and not yet answered: {id, art, seit}
        self.letzter_auftrag = None  # {id, art, status, von, bis}
        self.ende_grund = ""        # why the last session ended, as far as the server knows
        self.ende_zeit = 0.0
        self.ereignisse = []        # [[epoch, text], ...] ring
        self.zustand_alt = "nie"
        self.alt_gesehen = 0.0      # last contact as stored before this server start
        self.sitzung_ende_gemeldet = True
        self.klopfen = 0            # greetings (osum-bruecke) since the last sign-in attempt that got further
        self.klopf_seit = 0.0
        self.klopf_zeit = 0.0
        self.ich_zeit = 0.0         # last time the device got as far as `ich`

    def lebt(self):
        return (jetzt() - self.gesehen) < TOT_S

    def als_json(self):
        return {
            "kennung": self.kennung,
            "gekoppelt": self.gekoppelt,
            "gesperrt": self.gesperrt,
            "verbunden": self.lebt(),
            "zuletzt_gesehen_s": round(jetzt() - self.gesehen, 1)
                                 if self.gesehen else None,
            "verbunden_seit_s": round(jetzt() - self.seit, 1)
                                if self.seit else None,
            "offene_auftraege": len(self.auftraege),
            "info": self.info,
            "zustand": zustand(self),
            "letzter_kontakt_utc": utc_text(self.gesehen or self.alt_gesehen),
            "mac": self.mac,
        }



# ====================================================================
# WARUM OFFLINE (05.10.2026)
# ====================================================================
#
# Until now the server only knew "seen < 90 s ago". When the Dell went
# silent there was NO record of how: no end event, no last contact that
# survived a restart, no difference between "busy with a long command"
# (the old client does not poll while a command runs, up to 1200 s) and
# "gone". This block adds that. It never invents a cause: when the wire
# shows nothing, the answer says so.

def utc_text(t):
    if not t:
        return None
    return datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")


def wien_text(t):
    if not t:
        return None
    try:
        import zoneinfo
        z = zoneinfo.ZoneInfo("Europe/Vienna")
        return datetime.datetime.fromtimestamp(t, z).strftime("%Y-%m-%d %H:%M:%S %Z")
    except Exception:
        return None


def ereignis(g, text, laut=True):
    """Append to the device's event ring (kept in status.json) and log it."""
    with _sperre:
        g.ereignisse.append([round(jetzt(), 1), text])
        del g.ereignisse[:-EREIGNIS_MAX]
    if laut:
        melde("%s: %s" % (g.kennung, text))


def zustand(g):
    """nie | online | beschaeftigt | sauber_beendet | stumm"""
    if g.klopf_zeit and jetzt() - g.klopf_zeit < 150 and g.klopf_zeit > g.ich_zeit \
            and g.klopf_zeit > (g.gesehen or 0):
        return "klopft"
    if not g.gesehen and not g.alt_gesehen:
        return "nie"
    if g.gesehen and g.lebt():
        return "online"
    if g.gesehen and g.laufend and (jetzt() - g.laufend.get("seit", 0)) < BUSY_GRACE_S \
            and (jetzt() - g.gesehen) < BUSY_GRACE_S:
        return "beschaeftigt"
    if g.gesehen and g.tschuess:
        return "sauber_beendet"
    return "stumm"


def puls_gesehen(g):
    """Called for every poll / keepalive of a signed-in device."""
    with _sperre:
        t = jetzt()
        if g.gesehen:
            luecke = t - g.gesehen
            if luecke > g.max_luecke:
                g.max_luecke = luecke
            if luecke > TOT_S and g.seit and not g.tschuess:
                grund = ("Luecke %d s zwischen zwei Meldungen" % luecke)
                if g.laufend:
                    grund += " (Auftrag %s %s lief)" % (g.laufend.get("id"), g.laufend.get("art"))
                ereignis(g, grund)
        g.gesehen = t
        g.pulse += 1
        g.tschuess = False


def sitzung_beginnt(g, ip):
    """Called after a successful signature check (both transports)."""
    with _sperre:
        t = jetzt()
        if g.gesehen and not g.sitzung_ende_gemeldet:
            dauer = (g.gesehen - g.seit) if g.seit else 0
            stille = t - g.gesehen
            ereignis(g, "NEUE SITZUNG nach %d s ohne Meldung: die vorige (%d s, %d Meldungen, "
                     "laengste Luecke %d s) endete ohne Abmeldung%s"
                     % (stille, dauer, g.pulse, g.max_luecke,
                        "; Auftrag %s %s war unbeantwortet" % (g.laufend.get("id"), g.laufend.get("art"))
                        if g.laufend else ""))
        elif not g.gesehen and g.alt_gesehen:
            ereignis(g, "ERSTE SITZUNG nach Server-Start; letzter Kontakt davor: %s (vor %d s)"
                     % (utc_text(g.alt_gesehen), t - g.alt_gesehen))
        if g.laufend:
            ereignis(g, "Auftrag %s %s ging mit der alten Sitzung verloren"
                     % (g.laufend.get("id"), g.laufend.get("art")))
            g.laufend = None
        g.sitzungen += 1
        g.pulse = 0
        g.max_luecke = 0.0
        g.tschuess = False
        g.letzte_ip = ip
        g.ende_grund = ""
        g.sitzung_ende_gemeldet = False
        g.zustand_alt = "online"
        verwerfe_alte(g)
        status_schreiben()


def verwerfe_alte(g):
    """A job that waited longer than its TTL is dropped: a device coming back
    after hours must not run commands somebody queued for an earlier moment."""
    with _sperre:
        t = jetzt()
        behalten = []
        for a in g.auftraege:
            ttl = a.get("ttl_s", JOB_TTL_S)
            if ttl and t - a.get("ts", t) > ttl:
                ereignis(g, "AUFTRAG VERWORFEN (veraltet, %d s alt): id=%s art=%s"
                         % (t - a.get("ts", t), a.get("id"), a.get("art")))
            else:
                behalten.append(a)
        g.auftraege[:] = behalten


def job_ausgegeben(g, a):
    with _sperre:
        g.laufend = {"id": a.get("id"), "art": a.get("art"), "seit": jetzt()}
        g.letzter_auftrag = {"id": a.get("id"), "art": a.get("art"), "status": "laeuft",
                             "von": jetzt(), "bis": None}


def job_fertig(g, aid, status):
    with _sperre:
        la = g.laufend
        if la and str(la.get("id")) == str(aid):
            g.laufend = None
        if g.letzter_auftrag and str(g.letzter_auftrag.get("id")) == str(aid):
            g.letzter_auftrag["status"] = status
            g.letzter_auftrag["bis"] = jetzt()


def status_pfad():
    return os.path.join(_wurzel, STATUS_NAME)


def status_schreiben():
    with _sperre:
        d = {"_server_start": SERVER_START}
        for k, g in _geraete.items():
            if not (g.gesehen or g.alt_gesehen or g.ereignisse or g.klopf_zeit):
                continue
            d[k] = {"gesehen": g.gesehen or g.alt_gesehen, "ip": g.letzte_ip, "seit": g.seit,
                    "commit": (g.info or {}).get("commit", ""), "sitzungen": g.sitzungen,
                    "pulse": g.pulse, "max_luecke": g.max_luecke, "tschuess": g.tschuess,
                    "laufend": g.laufend, "letzter_auftrag": g.letzter_auftrag,
                    "ende_grund": g.ende_grund, "ende_zeit": g.ende_zeit, "mac": g.mac,
                    "ereignisse": g.ereignisse[-EREIGNIS_MAX:],
                    "ende_gemeldet": g.sitzung_ende_gemeldet, "klopfen": g.klopfen,
                    "klopf_seit": g.klopf_seit, "klopf_zeit": g.klopf_zeit}
    tmp = status_pfad() + ".neu"
    try:
        with open(tmp, "w") as f:
            json.dump(d, f, indent=1)
        os.chmod(tmp, 0o600)
        os.replace(tmp, status_pfad())
    except OSError as e:
        melde("status.json nicht geschrieben: %s" % e)


def status_lesen():
    try:
        with open(status_pfad()) as f:
            d = json.load(f)
    except Exception:
        return
    with _sperre:
        for k, v in d.items():
            if k.startswith("_") or not isinstance(v, dict):
                continue
            g = hol_geraet(k)
            g.alt_gesehen = float(v.get("gesehen") or 0)
            g.letzte_ip = v.get("ip", "")
            g.sitzungen = int(v.get("sitzungen") or 0)
            g.laufend = None
            g.letzter_auftrag = v.get("letzter_auftrag")
            g.ende_grund = v.get("ende_grund", "")
            g.ende_zeit = float(v.get("ende_zeit") or 0)
            g.ereignisse = v.get("ereignisse", [])[-EREIGNIS_MAX:]
            g.seit_alt = float(v.get("seit") or 0)
            g.zustand_alt = "stumm"
            g.sitzung_ende_gemeldet = True
            g.klopfen = int(v.get("klopfen") or 0)
            g.klopf_seit = float(v.get("klopf_seit") or 0)
            g.klopf_zeit = float(v.get("klopf_zeit") or 0)
            if v.get("mac") and not g.mac:
                g.mac = v["mac"]
            if g.alt_gesehen and jetzt() - g.alt_gesehen < 600:
                ereignis(g, "SERVER NEU GESTARTET; das Geraet war zuletzt vor %d s da (Sitzungsmarken sind weg, "
                         "es muss sich neu anmelden)" % (jetzt() - g.alt_gesehen))


def waechter():
    """Every few seconds: notice the moment a device goes from alive to silent
    and write down what the server knew at that moment."""
    letzte_sicherung = 0.0
    while True:
        time.sleep(WAECHTER_S)
        try:
            geaendert = False
            with _sperre:
                for g in list(_geraete.values()):
                    z = zustand(g)
                    alt = g.zustand_alt
                    if z != alt:
                        geaendert = True
                        g.zustand_alt = z
                        stille = jetzt() - g.gesehen if g.gesehen else 0
                        dauer = (g.gesehen - g.seit) if g.seit and g.gesehen else 0
                        if z == "beschaeftigt":
                            ereignis(g, "BESCHAEFTIGT: Auftrag %s %s laeuft seit %d s; der Helfer meldet sich "
                                     "waehrend eines Befehls nicht (bis zu 1200 s) -- kein Ausfall"
                                     % (g.laufend.get("id"), g.laufend.get("art"),
                                        jetzt() - g.laufend.get("seit", jetzt())))
                        elif z == "sauber_beendet":
                            g.ende_grund = "sauber abgemeldet (tschuess)"
                            g.ende_zeit = g.gesehen
                            g.sitzung_ende_gemeldet = True
                            ereignis(g, "GETRENNT: sauber abgemeldet nach %d s Sitzung" % dauer)
                        elif z == "stumm":
                            extra = ""
                            if g.laufend:
                                extra = (" Auftrag %s %s war unbeantwortet seit %d s -- der Helfer hat sich "
                                         "beim Auftrag aufgehaengt oder das Geraet starb waehrenddessen."
                                         % (g.laufend.get("id"), g.laufend.get("art"),
                                            jetzt() - g.laufend.get("seit", jetzt())))
                            g.ende_grund = ("stumm: seit %d s keine Meldung, keine Abmeldung, kein Fehler am Draht"
                                            % stille) + extra
                            g.ende_zeit = g.gesehen
                            ereignis(g, "STUMM: letzte Meldung %s, Sitzung dauerte %d s, %d Meldungen, "
                                     "laengste Luecke %d s, IP %s, Commit %s.%s Der Server kann nicht sehen, ob "
                                     "das Geraet aus ist, abgestuerzt, im Ruhezustand oder das Netz weg ist."
                                     % (utc_text(g.gesehen), dauer, g.pulse, g.max_luecke, g.letzte_ip or "?",
                                        (g.info or {}).get("commit", "") or "?", extra))
                        elif z == "klopft":
                            ereignis(g, "KLOPFT NUR AN: seit %s %d Begruessungen (etwa alle 30 s), aber nie ein `ich` "
                                     "danach. Das Geraet LEBT und erreicht den Server; die Anmeldung scheitert auf dem "
                                     "Geraet selbst, bevor es etwas Signiertes senden kann (Code: /bin/jsig nicht "
                                     "startbar, z. B. Prozesstafel voll, oder Arbeitsdatei nicht schreibbar). "
                                     "Letzter echter Kontakt: %s."
                                     % (utc_text(g.klopf_seit), g.klopfen, utc_text(g.gesehen or g.alt_gesehen)))
                        elif z == "online" and alt in ("stumm", "beschaeftigt", "sauber_beendet", "klopft"):
                            ereignis(g, "WIEDER DA (war %s)" % alt)
                    if z in ("stumm", "sauber_beendet"):
                        verwerfe_alte(g)
            if geaendert or jetzt() - letzte_sicherung > 60:
                letzte_sicherung = jetzt()
                status_schreiben()
        except Exception as e:                       # the watcher must never die
            melde("Waechter-Fehler: %s" % e)


def warum_text(g):
    z = zustand(g)
    t = g.gesehen or g.alt_gesehen
    vor = jetzt() - t if t else None
    if z == "nie":
        return "Das Geraet hat sich noch nie gemeldet."
    if z == "online":
        return "online, Sitzung seit %d s, letzte Meldung vor %d s." % (jetzt() - g.seit, vor)
    if z == "beschaeftigt":
        return ("arbeitet seit %d s an Auftrag %s (%s); aeltere Helfer melden sich dabei nicht -- "
                "nicht offline, nur still." % (jetzt() - g.laufend["seit"], g.laufend["id"], g.laufend["art"]))
    if z == "sauber_beendet":
        return "hat sich vor %d s mit tschuess abgemeldet." % vor
    if z == "klopft":
        return ("LEBT, KOMMT ABER NICHT HEREIN: seit %s (%d Begruessungen, ca. alle 30 s) klopft das Geraet an, sendet "
                "aber nie `ich`. Die Anmeldung scheitert auf dem Geraet (wahrscheinlich kein freier Prozess-Slot fuer "
                "/bin/jsig). Das Geraet laeuft also noch: ein Neustart (Strom aus/an) loest es, Wake-on-LAN hilft nicht."
                % (utc_text(g.klopf_seit), g.klopfen))
    if not g.gesehen:
        return ("seit dem Server-Start (%s) nicht gesehen; letzter Kontakt davor: %s (vor %d s)."
                % (utc_text(SERVER_START), utc_text(g.alt_gesehen), vor))
    return ("STUMM seit %d s (letzte Meldung %s). Kein Abmelde-Wort, kein Fehler, keine Server-Neustart-Luecke. "
            "Ursache aus Serversicht NICHT bestimmbar: Geraet aus / abgestuerzt / Ruhezustand / Netz weg. %s"
            % (vor, utc_text(t), ("Offener Auftrag: %s %s." % (g.laufend["id"], g.laufend["art"])) if g.laufend else ""))


def warum_json(g):
    t = g.gesehen or g.alt_gesehen
    return {
        "kennung": g.kennung, "zustand": zustand(g), "kurz": warum_text(g),
        "letzter_kontakt_utc": utc_text(t), "letzter_kontakt_wien": wien_text(t),
        "vor_s": round(jetzt() - t, 1) if t else None, "ip": g.letzte_ip or (g.info or {}).get("ip_extern"),
        "ip_hinweis": "ip ist die Adresse des Weiterreichers im Serverhaus (X-Von), nicht die Heimadresse des Geraets"
                      if (g.letzte_ip or "").startswith("192.168.1.") else "",
        "commit": (g.info or {}).get("commit", ""), "sitzungen_seit_status": g.sitzungen,
        "sitzung_dauer_s": round((g.gesehen - g.seit), 1) if g.seit and g.gesehen else None,
        "meldungen_in_sitzung": g.pulse, "laengste_luecke_s": round(g.max_luecke, 1),
        "klopfen": g.klopfen, "klopft_seit_utc": utc_text(g.klopf_seit) if g.klopf_seit else None,
        "letztes_klopfen_utc": utc_text(g.klopf_zeit) if g.klopf_zeit else None,
        "laufender_auftrag": g.laufend, "letzter_auftrag": g.letzter_auftrag,
        "offene_auftraege": len(g.auftraege), "ende_grund": g.ende_grund, "mac": g.mac,
        "server_start_utc": utc_text(SERVER_START), "server_laeuft_s": round(jetzt() - SERVER_START),
        "ereignisse": [[utc_text(e[0]), e[1]] for e in g.ereignisse[-25:]],
    }


def magic_paket(mac):
    h = re.sub(r"[^0-9a-fA-F]", "", mac)
    if len(h) != 12:
        raise ValueError("MAC muss 12 Hexziffern haben")
    b = bytes.fromhex(h)
    return b"\xff" * 6 + b * 16


def mac_norm(mac):
    """aabbccddeeff / AA-BB-.. / aa:bb:.. -> aa:bb:cc:dd:ee:ff (raises ValueError)"""
    h = re.sub(r"[^0-9a-fA-F]", "", mac).lower()
    if len(h) != 12:
        raise ValueError("MAC muss 12 Hexziffern haben")
    return ":".join(h[i:i + 2] for i in range(0, 12, 2))


def wol_senden(mac, ziele, port=9):
    import socket
    paket = magic_paket(mac)
    gesendet = []
    for z in ziele:
        for p in (port, 7):
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            try:
                s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
                s.sendto(paket, (z, p))
                gesendet.append("%s:%d" % (z, p))
            except OSError as e:
                gesendet.append("%s:%d FEHLER %s" % (z, p, e))
            finally:
                s.close()
    return gesendet


SERVER_START = time.time()
_unbekannt = {}                   # wire id -> last time it was logged as unknown


def hol_geraet(kennung, anlegen=True):
    with _sperre:
        g = _geraete.get(kennung)
        if g is None and anlegen:
            g = Geraet(kennung)
            _geraete[kennung] = g
        return g


def ablage(kennung):
    p = os.path.join(_wurzel, "geraete", sauber(kennung))
    os.makedirs(p, exist_ok=True)
    return p


def zustand_schreiben():
    """Kopplungen ueberleben einen Neustart des Dienstes."""
    with _sperre:
        d = {}
        for k, g in _geraete.items():
            if g.gekoppelt or g.gesperrt:
                d[k] = {"pubkey": g.pubkey, "geheim": g.geheim,
                        "gekoppelt": g.gekoppelt, "gesperrt": g.gesperrt,
                        "info": g.info, "mac": g.mac}
    tmp = os.path.join(_wurzel, "koppelbuch.json.neu")
    with open(tmp, "w") as f:
        json.dump(d, f, indent=1)
    os.chmod(tmp, 0o600)
    os.replace(tmp, os.path.join(_wurzel, "koppelbuch.json"))


def zustand_lesen():
    p = os.path.join(_wurzel, "koppelbuch.json")
    if not os.path.exists(p):
        return
    try:
        with open(p) as f:
            d = json.load(f)
    except Exception as e:
        melde("koppelbuch unlesbar: %s" % e)
        return
    with _sperre:
        for k, v in d.items():
            g = hol_geraet(k)
            g.pubkey = v.get("pubkey")
            g.geheim = v.get("geheim")
            g.gekoppelt = bool(v.get("gekoppelt"))
            g.gesperrt = bool(v.get("gesperrt"))
            g.info = v.get("info") or {}
            g.mac = v.get("mac", "") or ""
    melde("Koppelbuch gelesen: %d Geraet(e)" % len(d))


class Griff(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "OrientBruecke/1"

    def log_message(self, fmt, *args):
        pass                                 # wir protokollieren selbst

    # ---------------------------------------------------- Werkzeuge

    def rumpf_lesen(self, grenze=MAX_RUMPF):
        try:
            n = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            self.fehler(400, "bad Content-Length")
            return None
        if n < 0 or n > grenze:
            self.fehler(413, "body too large")
            return None
        daten = b""
        rest = n
        while rest > 0:
            st = self.rfile.read(min(rest, 65536))
            if not st:
                break
            daten += st
            rest -= len(st)
        return daten

    def json_lesen(self):
        roh = self.rumpf_lesen(MAX_AUFTRAG)
        if roh is None:
            return None
        try:
            return json.loads(roh.decode("utf-8"))
        except Exception:
            self.fehler(400, "bad json")
            return None

    def antwort(self, obj, code=200):
        roh = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(roh)))
        self.end_headers()
        try:
            self.wfile.write(roh)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def fehler(self, code, text):
        self.antwort({"fehler": text}, code)

    def vonwo(self):
        """Die ECHTE Gegenstelle, nicht der Weiterreicher.

        Anfragen kommen durch `orientstore/werkzeug/diagnose_server.py`
        herein, also steht in `client_address` immer 127.0.0.1. Der
        Weiterreicher setzt deshalb `X-Von`. Dieser Kopf wird NUR
        geglaubt, wenn die Verbindung wirklich von der Rueckschleife
        kommt -- sonst duerfte sich jeder seine Herkunft aussuchen.
        """
        ist = self.client_address[0]
        if ist in ("127.0.0.1", "::1"):
            v = self.headers.get("X-Von")
            if v:
                return sauber(v, 45)
        return ist

    def ist_verwalter(self):
        """Nur JARVIS selbst darf Auftraege stellen und koppeln.

        Der Verwalterschluessel steht in einer Datei, die nur root
        lesen kann. Ohne ihn ist /bruecke/auftrag nicht bedienbar --
        sonst koennte jeder, der die Adresse kennt, Befehle auf
        Justins Rechner absetzen.
        """
        soll = self.server.verwalter
        ist = self.headers.get("X-Bruecke-Verwalter", "")
        return bool(soll) and hmac.compare_digest(soll, ist)

    # ------------------------------------------------------- GET

    def do_GET(self):
        pfad = self.path.split("?")[0].rstrip("/")
        if pfad == "/bruecke/geraete":
            if not self.ist_verwalter():
                self.fehler(403, "kein Verwalterschluessel")
                return
            with _sperre:
                liste = [g.als_json() for g in _geraete.values()]
            self.antwort({"geraete": liste})
            return
        if pfad == "/bruecke/holen":
            self.holen()
            return
        if pfad == "/bruecke/warum":
            if not self.ist_verwalter():
                self.fehler(403, "kein Verwalterschluessel")
                return
            q = self.path.split("?", 1)[1] if "?" in self.path else ""
            ziel = ""
            for kv in q.split("&"):
                if kv.startswith("geraet="):
                    ziel = sauber(kv[7:])
            with _sperre:
                liste = [warum_json(g) for k, g in _geraete.items()
                         if (not ziel or k == ziel) and (g.gesehen or g.alt_gesehen or g.ereignisse or g.klopf_zeit)]
            self.antwort({"geraete": liste})
            return
        if pfad == "/bruecke/gesund":
            self.antwort({"gesund": True, "geraete": len(_geraete),
                          "ed25519": HAT_ED25519})
            return
        if pfad.startswith("/bruecke/dl/"):
            self.dl(pfad)
            return
        self.fehler(404, "kein solcher Pfad")

    # PRIVATE DOWNLOADS FOR A DEVICE (27.09.2026). Update files for a
    # personal stick carry the device key and the password hashes, so they
    # must never sit in the public store (/srv/store). They go into
    # <wurzel>/dl/<token>/ instead, where <token> is 32+ random hex digits
    # made by the admin for one update; the device fetches
    # /bruecke/dl/<token>/<name> over the same HTTPS path as the bridge.
    # No listing, no dots, no subdirectories; Range is honoured so that
    # `fetch -b` can resume.
    def dl(self, pfad):
        teile = pfad.split("/")
        if len(teile) != 5:
            self.fehler(404, "kein solcher Pfad")
            return
        token, name = teile[3], teile[4]
        if (len(token) < 32 or not all(c in "0123456789abcdef" for c in token)
                or not name or name.startswith(".") or "/" in name
                or not all(c.isalnum() or c in "._-" for c in name)):
            self.fehler(404, "kein solcher Pfad")
            return
        datei = os.path.join(_wurzel, "dl", token, name)
        if not os.path.isfile(datei):
            self.fehler(404, "kein solcher Pfad")
            return
        groesse = os.path.getsize(datei)
        anfang = 0
        rng = self.headers.get("Range", "")
        if rng.startswith("bytes=") and rng[6:].split("-")[0].isdigit():
            anfang = min(int(rng[6:].split("-")[0]), groesse)
        melde("DL %s/%s ab %d (%d)" % (token[:8], name, anfang, groesse))
        self.send_response(206 if anfang else 200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(groesse - anfang))
        if anfang:
            self.send_header("Content-Range", "bytes %d-%d/%d"
                             % (anfang, groesse - 1, groesse))
        self.end_headers()
        try:
            with open(datei, "rb") as fh:
                fh.seek(anfang)
                while True:
                    stueck = fh.read(65536)
                    if not stueck:
                        break
                    self.wfile.write(stueck)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def holen(self):
        if not self.ist_verwalter():
            self.fehler(403, "kein Verwalterschluessel")
            return
        frage = {}
        if "?" in self.path:
            for teil in self.path.split("?", 1)[1].split("&"):
                if "=" in teil:
                    k, v = teil.split("=", 1)
                    frage[k] = v
        kennung = sauber(frage.get("geraet", ""))
        aid = sauber(frage.get("id", ""), 32)
        g = hol_geraet(kennung, anlegen=False)
        if g is None:
            self.fehler(404, "kein solches Geraet")
            return
        # Bis zu WARTE_S auf das Ergebnis warten -- der Aufrufer will
        # das Bild, nicht ein "noch nicht".
        ende = jetzt() + WARTE_S
        with _sperre:
            while aid not in g.ergebnisse and jetzt() < ende:
                g.wecker.wait(timeout=max(0.1, ende - jetzt()))
            paar = g.ergebnisse.pop(aid, None)
        if paar is None:
            self.fehler(404, "noch kein Ergebnis")
            return
        kopf, rumpf = paar
        self.send_response(200)
        self.send_header("Content-Type",
                         kopf.get("typ", "application/octet-stream"))
        self.send_header("X-Bruecke-Status", str(kopf.get("status", "")))
        self.send_header("Content-Length", str(len(rumpf)))
        self.end_headers()
        try:
            self.wfile.write(rumpf)
        except (BrokenPipeError, ConnectionResetError):
            pass

    # ------------------------------------------------------ POST

    def do_POST(self):
        pfad = self.path.split("?")[0].rstrip("/")
        if pfad == "/bruecke/anmelden":
            self.anmelden()
        elif pfad == "/bruecke/warten":
            self.warten()
        elif pfad == "/bruecke/ergebnis":
            self.ergebnis()
        elif pfad == "/bruecke/auftrag":
            self.auftrag()
        elif pfad == "/bruecke/koppeln":
            self.koppeln()
        elif pfad == "/bruecke/draht":
            self.draht()
        elif pfad == "/bruecke/wol":
            self.wol()
        else:
            self.fehler(404, "kein solcher Pfad")

    # ------------------------------------------------- die Anmeldung
    #
    # Ablauf, und jeder Schritt hat einen Grund:
    #
    #   1. Geraet schickt Kennung + oeffentlichen Schluessel.
    #   2. Ist es unbekannt: Server erzeugt einen KOPPLUNGSCODE und
    #      antwortet "kopplung-noetig". Das Geraet zeigt den Code auf
    #      dem BILDSCHIRM. Ein Mensch gibt ihn frei
    #      (POST /bruecke/koppeln). Ohne das geht es nicht weiter.
    #   3. Ist es gekoppelt: Server schickt eine ZUFALLSFORDERUNG.
    #      Das Geraet unterschreibt sie mit dem privaten Schluessel und
    #      meldet sich erneut. Stimmt die Unterschrift, gibt es eine
    #      Sitzungsmarke.
    #
    # Der Server weist sich seinerseits durch das TLS-Zertifikat von
    # store.fleitec.com aus -- das prueft das Geraet, bevor es
    # ueberhaupt etwas sendet.

    def anmelden(self):
        d = self.json_lesen()
        if d is None:
            return
        kennung = sauber(str(d.get("kennung", "")))
        if kennung == "unbekannt":
            self.fehler(400, "keine Kennung")
            return
        ip = self.vonwo()
        g = hol_geraet(kennung)

        with _sperre:
            if g.gesperrt:
                melde("ABGELEHNT (gesperrt): %s von %s" % (kennung, ip))
                self.fehler(403, "dieses Geraet ist gesperrt")
                return

            pub = str(d.get("pubkey", ""))[:64]

            # --- noch nicht gekoppelt: Code erzeugen, sonst nichts.
            if not g.gekoppelt:
                if not g.code:
                    g.code = "%06d" % secrets.randbelow(1000000)
                g.pubkey = pub or g.pubkey
                g.info = self.info_aus(d, ip)
                melde("KOPPLUNG NOETIG: %s (%s) Code %s"
                      % (kennung, ip, g.code))
                self.antwort({"zustand": "kopplung-noetig",
                              "code": g.code})
                return

            # --- gekoppelt: der Schluessel MUSS derselbe sein.
            if g.pubkey and pub and pub != g.pubkey:
                melde("ABGELEHNT (fremder Schluessel): %s von %s"
                      % (kennung, ip))
                self.fehler(403, "Schluessel passt nicht zur Kopplung")
                return

            sig = str(d.get("unterschrift", ""))
            forderung = str(d.get("forderung", ""))

            # Schritt A: keine Unterschrift dabei -> Forderung stellen.
            if not sig:
                g.forderung = secrets.token_hex(16)
                self.antwort({"zustand": "forderung",
                              "forderung": g.forderung})
                return

            # Schritt B: Unterschrift pruefen.
            erwartet = g.forderung
            if not erwartet or not hmac.compare_digest(erwartet, forderung):
                melde("ABGELEHNT (falsche Forderung): %s" % kennung)
                self.fehler(403, "Forderung stimmt nicht")
                return
            g.forderung = None          # eine Forderung gilt EINMAL

            # WAS UNTERSCHRIEBEN WIRD, BESTIMMT DAS GERAET -- NICHT DER
            # SERVER.
            #
            # Hier stand einmal `("bruecke:" + kennung + ":" +
            # forderung)`, und das war eine Erfindung dieses Servers.
            # Osums `kernel/user/jsig.fi` kennt genau einen Auftrag:
            #
            #     jsig unterschreibe <hex>   unterschreibt diese Oktette
            #
            # Es unterschreibt die OKTETTE DER FORDERUNG, sonst nichts.
            # Ein Server, der etwas anderes erwartet, lehnt jede
            # richtige Unterschrift ab -- gemessen, "ABGELEHNT vom
            # Dienst: Unterschrift falsch", bei einem Geraet mit dem
            # richtigen Schluessel.
            #
            # BEIDE FORMEN WERDEN GEPRUEFT, und die Reihenfolge sagt,
            # welche gemeint ist: zuerst die rohe Forderung (das ist
            # das Protokoll aus Runde BRIDGE, gegen das 113 Zusagen
            # gemessen sind), danach die Form mit Vorspann fuer
            # Gegenstellen, die sie benutzen. Das ist keine
            # Nachlaessigkeit: die rohe Forderung ist 16 zufaellige
            # Oktette vom Server, gilt EINMAL und wird nach dem ersten
            # Versuch verworfen -- sie ist als Beweis genau so gut wie
            # die laengere Form.
            try:
                roh_ford = bytes.fromhex(forderung)
            except ValueError:
                roh_ford = b""
            nachricht = ("bruecke:" + kennung + ":" + forderung).encode()
            ok = pruefe_unterschrift(g.pubkey, roh_ford, sig)
            if ok is False:
                ok = pruefe_unterschrift(g.pubkey, nachricht, sig)
            if ok is None:              # kein Ed25519 -> HMAC-Weg
                if not g.geheim:
                    self.fehler(403, "kein Geheimnis vereinbart")
                    return
                soll = hmac.new(bytes.fromhex(g.geheim), roh_ford,
                                hashlib.sha256).hexdigest()
                soll2 = hmac.new(bytes.fromhex(g.geheim), nachricht,
                                 hashlib.sha256).hexdigest()
                ok = (hmac.compare_digest(soll, sig)
                      or hmac.compare_digest(soll2, sig))
            if not ok:
                melde("ABGELEHNT (Unterschrift falsch): %s von %s"
                      % (kennung, ip))
                self.fehler(403, "Unterschrift falsch")
                return

            g.marke = secrets.token_hex(24)
            g.marke_bis = jetzt() + MARKE_S
            sitzung_beginnt(g, ip)
            g.gesehen = jetzt()
            g.seit = jetzt()
            g.info = self.info_aus(d, ip)
            melde("ANGEMELDET: %s (%s) %s"
                  % (kennung, ip, g.info.get("rechner", "")))
            self.antwort({"zustand": "willkommen", "marke": g.marke,
                          "gueltig_s": MARKE_S})

    def info_aus(self, d, ip):
        i = d.get("info") or {}
        return {
            "rechner": str(i.get("rechner", ""))[:64],
            "commit": str(i.get("commit", ""))[:40],
            "aufloesung": str(i.get("aufloesung", ""))[:24],
            "ip_intern": str(i.get("ip", ""))[:40],
            "ip_extern": ip,
            "laufzeit_s": i.get("laufzeit_s"),
        }

    def marke_pruefen(self, d):
        """Gibt das Geraet zurueck -- oder None, und hat dann geantwortet."""
        kennung = sauber(str(d.get("kennung", "")))
        marke = str(d.get("marke", ""))
        g = hol_geraet(kennung, anlegen=False)
        if g is None or not g.gekoppelt or g.gesperrt:
            self.fehler(403, "nicht gekoppelt")
            return None
        if not g.marke or not hmac.compare_digest(g.marke, marke):
            self.fehler(403, "Marke ungueltig")
            return None
        if jetzt() > g.marke_bis:
            self.fehler(403, "Marke abgelaufen")
            return None
        g.gesehen = jetzt()
        return g

    # --------------------------------------------- das lange Polling

    def warten(self):
        d = self.json_lesen()
        if d is None:
            return
        with _sperre:
            g = self.marke_pruefen(d)
            if g is None:
                return
            ende = jetzt() + WARTE_S
            puls_gesehen(g)
            verwerfe_alte(g)
            while not g.auftraege and jetzt() < ende:
                g.wecker.wait(timeout=max(0.1, ende - jetzt()))
                g.gesehen = jetzt()
            if g.auftraege:
                a = g.auftraege.pop(0)
                job_ausgegeben(g, a)
                melde("AUFTRAG -> %s: %s %s"
                      % (g.kennung, a.get("art"), a.get("ziel", "")))
                self.antwort({"auftrag": a})
            else:
                self.antwort({"auftrag": None})

    # ------------------------------------------------- das Ergebnis

    def ergebnis(self):
        kennung = sauber(self.headers.get("X-Bruecke-Geraet", ""))
        marke = self.headers.get("X-Bruecke-Marke", "")
        aid = sauber(self.headers.get("X-Bruecke-Id", ""), 32)
        status = self.headers.get("X-Bruecke-Status", "ok")[:64]
        typ = self.headers.get("X-Bruecke-Typ",
                               "application/octet-stream")[:64]
        g = hol_geraet(kennung, anlegen=False)
        if (g is None or not g.gekoppelt or g.gesperrt or not g.marke
                or not hmac.compare_digest(g.marke, marke)):
            self.fehler(403, "Marke ungueltig")
            return
        roh = self.rumpf_lesen()
        if roh is None:
            return
        with _sperre:
            g.gesehen = jetzt()
            g.ergebnisse[aid] = ({"status": status, "typ": typ}, roh)
            job_fertig(g, aid, status)
            g.wecker.notify_all()

        # Auf die Platte, damit ein Bild auch dann noch da ist, wenn
        # niemand gerade danach fragt. Der NAME kommt vom Server.
        endung = ".png" if "png" in typ else (
            ".txt" if "text" in typ else ".bin")
        ordner = ablage(kennung)
        name = "%s-%s%s" % (datetime.datetime.now().strftime("%H%M%S"),
                            aid or "ohne", endung)
        ziel = os.path.join(ordner, name)
        try:
            with open(ziel, "wb") as f:
                f.write(roh)
            dateien = sorted(os.listdir(ordner))
            for alt in dateien[:-BEHALTEN]:
                try:
                    os.remove(os.path.join(ordner, alt))
                except OSError:
                    pass
        except OSError as e:
            melde("Ablage fehlgeschlagen: %s" % e)
        melde("ERGEBNIS <- %s: id=%s status=%s %d Oktett -> %s"
              % (kennung, aid, status, len(roh), ziel))
        self.antwort({"angenommen": True, "oktette": len(roh),
                      "ablage": ziel})

    # ------------------------------------ was JARVIS in die Schlange legt

    def auftrag(self):
        if not self.ist_verwalter():
            self.fehler(403, "kein Verwalterschluessel")
            return
        d = self.json_lesen()
        if d is None:
            return
        kennung = sauber(str(d.get("geraet", "")))
        g = hol_geraet(kennung, anlegen=False)
        if g is None:
            self.fehler(404, "kein solches Geraet")
            return
        art = str(d.get("art", ""))[:24]
        # E-001 (04.10.2026): job kinds in English are accepted and turned
        # into the German internal names; on the wire to the device the
        # German names stay until BRUECKE_JOB_KINDS=en is set (a device of
        # a6dd7fad or older does not know the English ones).
        art = JOB_KINDS_DE.get(art, art)
        if art not in ("system", "foto", "befehl", "lies", "schreib",
                       "liste", "protokoll", "taste", "maus", "knopf",
                       "scan", "eingabe"):
            self.fehler(400, "unbekannte Auftragsart")
            return
        with _sperre:
            g.zaehler += 1
            aid = "%d" % g.zaehler
            a = {"id": aid, "art": art, "ts": jetzt(),
                 "ziel": str(d.get("ziel", ""))[:512],
                 "wert": str(d.get("wert", ""))[:MAX_WERT]}
            if "ttl_s" in d:                       # 0 = never expires
                try:
                    a["ttl_s"] = max(0, int(d["ttl_s"]))
                except (TypeError, ValueError):
                    pass
            g.auftraege.append(a)
            g.wecker.notify_all()
        self.antwort({"id": aid, "eingereiht": True,
                      "verbunden": g.lebt()})


    def wol(self):
        """Wake-on-LAN. Admin only. The packet leaves THIS server, so it only
        wakes a device in the same broadcast domain. For a device in another
        house, run tools/wol.py on a machine in that network (docs/WOL.md)."""
        if not self.ist_verwalter():
            self.fehler(403, "kein Verwalterschluessel")
            return
        d = self.json_lesen()
        if d is None:
            return
        mac = str(d.get("mac", ""))
        kennung = sauber(str(d.get("geraet", "")))
        g = hol_geraet(kennung, anlegen=False) if kennung else None
        if g is not None and not mac:
            mac = g.mac
        try:
            magic_paket(mac)
        except ValueError:
            self.fehler(400, "keine gueltige MAC (angeben oder vorher speichern)")
            return
        ziele = d.get("broadcast") or ["255.255.255.255"]
        if isinstance(ziele, str):
            ziele = [ziele]
        ziele = [str(z)[:40] for z in ziele][:8]
        if g is not None and d.get("speichern"):
            with _sperre:
                g.mac = mac_norm(mac)
                zustand_schreiben()
        out = wol_senden(mac, ziele)
        if g is not None:
            ereignis(g, "WOL gesendet an %s (MAC %s)" % (", ".join(ziele), mac))
        self.antwort({"gesendet": out, "mac": mac,
                      "hinweis": "Das Paket verlaesst den Server. Es weckt nur Geraete im selben Broadcast-Netz."})

    # ------------------------------------------- Kopplung und Sperre

    def koppeln(self):
        if not self.ist_verwalter():
            self.fehler(403, "kein Verwalterschluessel")
            return
        d = self.json_lesen()
        if d is None:
            return
        # PRE-PAIRING ("vorab"): the key was generated here and baked
        # into Justin's personal image, so the device never has to show
        # a code. Only the admin key can do this, same as "frei".
        if str(d.get("was", "")) == "vorab":
            pub = str(d.get("pubkey", "")).lower()
            if len(pub) != 64 or any(c not in "0123456789abcdef" for c in pub):
                self.fehler(400, "pubkey muss 64 Hexziffern sein")
                return
            kennung = "osum-" + pub[:12]
            g = hol_geraet(kennung)
            with _sperre:
                g.pubkey = pub
                g.gekoppelt = True
                g.gesperrt = False
                g.code = None
                zustand_schreiben()
            melde("VORAB GEKOPPELT: %s" % kennung)
            self.antwort({"gekoppelt": True, "kennung": kennung})
            return
        kennung = sauber(str(d.get("geraet", "")))
        g = hol_geraet(kennung, anlegen=False)
        if g is None:
            self.fehler(404, "kein solches Geraet")
            return
        was = str(d.get("was", "frei"))
        if was == "mac":
            try:
                magic_paket(str(d.get("mac", "")))
            except ValueError:
                self.fehler(400, "keine gueltige MAC")
                return
            with _sperre:
                g.mac = mac_norm(str(d.get("mac")))
                zustand_schreiben()
            melde("MAC gesetzt: %s = %s" % (kennung, g.mac))
            self.antwort({"mac": g.mac})
            return
        with _sperre:
            if was == "sperren":
                g.gesperrt = True
                g.gekoppelt = False
                g.marke = None
                melde("GESPERRT: %s" % kennung)
                zustand_schreiben()
                self.antwort({"gesperrt": True})
                return
            code = str(d.get("code", ""))
            if not g.code or not hmac.compare_digest(g.code, code):
                melde("KOPPLUNG ABGELEHNT (Code falsch): %s" % kennung)
                self.fehler(403, "Code stimmt nicht")
                return
            g.gekoppelt = True
            g.gesperrt = False
            g.code = None
            if not HAT_ED25519 and not g.geheim:
                g.geheim = secrets.token_hex(32)
            zustand_schreiben()
            melde("GEKOPPELT: %s" % kennung)
            self.antwort({"gekoppelt": True, "geheim": g.geheim})


    # ================================================ RUNDE MERGE-11
    # DER DRAHT: OSUMS ZEILENPROTOKOLL, GETUNNELT IN HTTPS-POSTS.
    #
    # WARUM ES DIESEN ENDPUNKT GIBT (gemessen, nicht vermutet).
    # `anschluss.py` uebersetzte zwischen Osums Zeilenprotokoll (TLS
    # 1.3 auf einem rohen Port) und diesem Dienst. Das setzt voraus,
    # dass der Anschluss VON JUSTINS NETZ AUS erreichbar ist -- also
    # eine Portfreigabe am Router. Die gibt es nicht. Ergebnis: sein
    # Rechner hat sich NIE gemeldet; im Koppelbuch standen nur zwei
    # Pruefstaende aus dem Hausnetz, beide gesperrt.
    #
    # Der einzige Weg, der aus einem fremden Heimnetz zuverlaessig
    # hinausgeht, ist 443 -- und der steht bereits:
    #     POST https://store.fleitec.com/bruecke/anmelden
    #         -> {"fehler": "keine Kennung"}
    # Das ist die Antwort DIESES Dienstes durch die Weiterreichung,
    # nicht ein 404 des Speicherdienstes.
    #
    # Also nimmt das Geraet diesen Weg -- mit UNVERAENDERTEM
    # Zeilenprotokoll. Der Rumpf einer Anfrage sind genau die Oktette,
    # die frueher in den TLS-Strom gingen; die Antwort genau die, die
    # zurueckkamen. Damit bleiben die 113 gemessenen Zusagen aus Runde
    # BRIDGE gueltig: derselbe Zustandsautomat, derselbe Handschlag,
    # dieselbe Ed25519-Pruefung -- es wechselt NUR der Transport.
    #
    # WAS DAS GERAET NICHT LERNEN MUSS: JSON und base64. Beides bleibt
    # hier. Auf dem Geraet kommt nur hinzu: eine POST-Zeile, ein
    # Host-Kopf, eine Laengenangabe. Das ist die kleinste Menge HTTP,
    # mit der man ueber 443 sprechen kann, und es ist die direkte
    # Antwort auf Einwand 1 im Kopf von anschluss.py (die
    # Angriffsflaeche von jarvisd klein halten).
    #
    # ZUSTAND. HTTP hat keine Verbindung, der Handschlag aber Schritte.
    # Die Zwischenstaende haengen deshalb am GERAET (`g.forderung`,
    # `g.marke`) -- denselben Feldern, die `anmelden()` benutzt. Diese
    # Tabelle haelt nur, was sonst nirgends steht: welche Kennung zu
    # welchem Draht gehoert.

    def draht(self):
        roh = self.rumpf_lesen(MAX_AUFTRAG)
        if roh is None:
            return
        sid = sauber(self.headers.get("X-Draht", ""), 64)
        if not self.headers.get("X-Draht"):
            # Before 05.10.2026 the forwarder dropped this header, so every device
            # shared the id "unbekannt" (and one device's state could overwrite
            # another's). Still served, but said out loud, once per 10 minutes.
            t = jetzt()
            if t - _unbekannt.get("(kein X-Draht)", 0) > 600:
                _unbekannt["(kein X-Draht)"] = t
                melde("WARNUNG: Anfrage ohne X-Draht -- die Weiterreichung gibt den Kopf nicht weiter; "
                      "alle Geraete teilen dann EINEN Draht-Zustand")
        if not sid:
            self.fehler(400, "kein X-Draht")
            return
        ip = self.vonwo()
        # A greeting alone (`osum-bruecke`) from a paired device: it is alive and reaches
        # the server. If `ich` never follows, the sign-in fails ON the device (found
        # 05.10.2026: the Dell knocked every 30 s for 13 h and never got past /bin/jsig).
        if roh.startswith(b"osum-bruecke") and len(sid) >= 12:
            g0 = hol_geraet("osum-" + sid[:12], anlegen=False)
            if g0 is not None and g0.gekoppelt and not g0.gesperrt:
                with _sperre:
                    if not g0.klopf_zeit or g0.klopf_zeit <= g0.ich_zeit:
                        g0.klopfen = 0
                        g0.klopf_seit = jetzt()
                    g0.klopfen += 1
                    g0.klopf_zeit = jetzt()
                    g0.letzte_ip = g0.letzte_ip or ip
            else:
                # unknown or unpaired wire id: say so once per 5 minutes (who is knocking?)
                t = jetzt()
                if t - _unbekannt.get(sid, 0) > 300:
                    _unbekannt[sid] = t
                    melde("BEGRUESSUNG von unbekannter/ungekoppelter Draht-Kennung %s (%s)" % (sid, ip))
        elif roh.startswith(b"ich "):
            g0 = hol_geraet("osum-" + sid[:12], anlegen=False)
            if g0 is not None:
                with _sperre:
                    g0.ich_zeit = jetzt()
        with _sperre:
            for k in [k for k, v in self.server.draehte.items()
                      if jetzt() - v.get("gesehen", 0) > DRAHT_TOT]:
                del self.server.draehte[k]
            st = self.server.draehte.setdefault(
                sid, {"kennung": None, "pub": None})
            st["gesehen"] = jetzt()
        aus = self._draht_schritt(st, roh, ip)
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(aus)))
        self.end_headers()
        try:
            self.wfile.write(aus)
        except (BrokenPipeError, ConnectionResetError):
            pass

    @staticmethod
    def _zeile_teilen(roh):
        """Kopfzeile + Nutzlast -- das Format, das `sende()` in
        kernel/app/jarvisd.fi schreibt: Felder, letztes Feld ist die
        Laenge, dann Umbruch, dann so viele Oktette."""
        i = roh.find(b"\n")
        if i < 0:
            return [], b""
        f = roh[:i].decode("utf-8", "replace").strip().split()
        n = int(f[-1]) if f and f[-1].isdigit() else 0
        return f, roh[i + 1:i + 1 + n]

    @staticmethod
    def _sende(kopf, nutz=b""):
        return (kopf + " " + str(len(nutz))).encode() + b"\n" + nutz

    def _weg(self, grund):
        return self._sende("weg " + grund.encode().hex())

    def _draht_schritt(self, st, roh, ip):
        f, nutz = self._zeile_teilen(roh)
        if not f:
            return self._weg("leere Zeile")
        wort = f[0]

        # ---- Begruessung: es folgt `ich`.
        if wort == "osum-bruecke":
            return b""

        # ---- Der oeffentliche Schluessel.
        if wort == "ich":
            pub = (f[1] if len(f) > 1 else "")[:64]
            kennung = "osum-" + pub[:12]
            st["kennung"] = kennung
            st["pub"] = pub
            g = hol_geraet(kennung)
            with _sperre:
                if g.gesperrt:
                    melde("ABGELEHNT (gesperrt): %s von %s" % (kennung, ip))
                    return self._weg("dieses Geraet ist gesperrt")
                if not g.gekoppelt:
                    if not g.code:
                        g.code = "%06d" % secrets.randbelow(1000000)
                    g.pubkey = pub or g.pubkey
                    g.info = self.info_aus({"info": {"ip": ip}}, ip)
                    zustand_schreiben()
                    melde("KOPPLUNG NOETIG: %s (%s) Code %s"
                          % (kennung, ip, g.code))
                    return self._sende("kopplung-noetig "
                                       + g.code.encode().hex())
                if g.pubkey and pub and pub != g.pubkey:
                    melde("ABGELEHNT (fremder Schluessel): %s von %s"
                          % (kennung, ip))
                    return self._weg("Schluessel passt nicht zur Kopplung")
                g.forderung = secrets.token_hex(16)
                return self._sende("frage " + g.forderung)

        kennung = st.get("kennung")
        if not kennung:
            return self._weg("kein Handschlag")
        g = hol_geraet(kennung, anlegen=False)
        if g is None:
            return self._weg("unbekanntes Geraet")

        # ---- Die Unterschrift. GENAU wie in `anmelden()`: geprueft
        #      wird zuerst die ROHE Forderung (das Protokoll aus Runde
        #      BRIDGE, gegen das die 113 Zusagen gemessen sind), danach
        #      die Form mit Vorspann. `jsig` unterschreibt die Oktette
        #      der Forderung, sonst nichts.
        if wort == "beweis":
            sig = (f[1] if len(f) > 1 else "")[:128]
            with _sperre:
                forderung = g.forderung
                if not forderung:
                    return self._weg("keine Forderung offen")
                g.forderung = None          # gilt EINMAL
                try:
                    roh_ford = bytes.fromhex(forderung)
                except ValueError:
                    roh_ford = b""
                nachricht = ("bruecke:" + kennung + ":" + forderung).encode()
                ok = pruefe_unterschrift(g.pubkey, roh_ford, sig)
                if ok is False:
                    ok = pruefe_unterschrift(g.pubkey, nachricht, sig)
                if ok is None:
                    if not g.geheim:
                        return self._weg("kein Geheimnis vereinbart")
                    soll = hmac.new(bytes.fromhex(g.geheim), roh_ford,
                                    hashlib.sha256).hexdigest()
                    soll2 = hmac.new(bytes.fromhex(g.geheim), nachricht,
                                     hashlib.sha256).hexdigest()
                    ok = (hmac.compare_digest(soll, sig)
                          or hmac.compare_digest(soll2, sig))
                if not ok:
                    melde("ABGELEHNT (Unterschrift falsch): %s von %s"
                          % (kennung, ip))
                    return self._weg("Unterschrift falsch")
                g.marke = secrets.token_hex(24)
                g.marke_bis = jetzt() + MARKE_S
                sitzung_beginnt(g, ip)
                g.gesehen = jetzt()
                g.seit = jetzt()
                g.info = self.info_aus({"info": {"ip": ip}}, ip)
                zustand_schreiben()
            melde("ANGEMELDET (Draht): %s (%s)" % (kennung, ip))
            return self._sende("willkommen")

        # Ab hier MUSS eine gueltige Marke stehen.
        if not g.marke or g.marke_bis < jetzt():
            ereignis(g, "weg gesendet: Sitzungsmarke fehlt oder abgelaufen (Server neu gestartet oder "
                     "12 h um); der Helfer muss sich neu anmelden", laut=False)
            return self._weg("nicht angemeldet")

        # ---- Keepalive while a long command runs (new clients). No job is
        #      handed out, nothing is answered.
        if wort == "lebt":
            with _sperre:
                g.gesehen = jetzt()
            return b""

        # ---- The device tells what only it knows: its MAC (for Wake-on-LAN),
        #      its image commit. `info mac=..;commit=..` as the payload.
        if wort == "info":
            try:
                kv = dict(x.split("=", 1) for x in nutz.decode("utf-8", "replace").split(";") if "=" in x)
            except Exception:
                kv = {}
            with _sperre:
                g.gesehen = jetzt()
                m = kv.get("mac", "")
                try:
                    m = mac_norm(m)
                    if g.mac != m:
                        g.mac = m
                        zustand_schreiben()
                        ereignis(g, "MAC gemeldet: %s" % g.mac)
                except ValueError:
                    pass
                if kv.get("commit"):
                    g.info["commit"] = kv["commit"][:40]
            return b""

        # ---- Arbeit holen. Leere Antwort = nichts zu tun; das Geraet
        #      fragt gleich wieder. Das ist das lange Polling, nur mit
        #      der Wartezeit auf der Geraeteseite.
        if wort == "puls":
            puls_gesehen(g)
            with _sperre:
                verwerfe_alte(g)
                auf = g.auftraege.pop(0) if g.auftraege else None
                if auf is not None:
                    job_ausgegeben(g, auf)
            if auf is None:
                return b""
            art = auf.get("art", "")
            nutz = b""
            if art == "schreib":
                # The path goes as the argument, the file content as the
                # PAYLOAD behind the line (`auftrag ... <laenge>`), which
                # is where jarvisd's `tue_schreib` reads it from. Before
                # 27.09.2026 the content was dropped and every write
                # produced an empty file. "b64:" in front = binary.
                inhalt = auf.get("ziel", "") or ""
                w = auf.get("wert", "") or ""
                if w.startswith("b64:"):
                    try:
                        nutz = base64.b64decode(w[4:])
                    except Exception:
                        nutz = b""
                else:
                    nutz = w.encode()
            elif art == "eingabe":
                inhalt = auf.get("wert", "") or auf.get("ziel", "")
            elif art in ("taste", "maus", "knopf", "scan"):
                # jarvisd knows ONE input job, `eingabe`, with the kind
                # as the first word: "taste <code> <mods>",
                # "maus <x> <y>", "knopf <mask> <down>".
                inhalt = art + " " + (auf.get("wert", "") or auf.get("ziel", ""))
                art = "eingabe"
            else:
                inhalt = auf.get("ziel", "") or auf.get("wert", "") or ""
            a1 = inhalt.encode().hex() if inhalt else "0"
            if os.environ.get("BRUECKE_JOB_KINDS") == "en":
                art = JOB_KINDS_EN.get(art, art)
            melde("AUFTRAG -> %s: id=%s art=%s"
                  % (kennung, auf.get("id", 0), art))
            return self._sende("auftrag %s %s %s 0"
                               % (auf.get("id", 0), art, a1), nutz)

        # ---- Ergebnis. Dieselbe Ablage wie `ergebnis()`.
        if wort == "fertig":
            aid = sauber(f[1] if len(f) > 1 else "0", 32)
            status = (f[2] if len(f) > 2 else "ok")[:64]
            typ = ("image/png" if nutz[:8] == b"\x89PNG\r\n\x1a\n"
                   else "text/plain; charset=utf-8")
            with _sperre:
                g.gesehen = jetzt()
                g.ergebnisse[aid] = ({"status": status, "typ": typ}, nutz)
                job_fertig(g, aid, status)
                g.wecker.notify_all()
            endung = ".png" if "png" in typ else ".txt"
            ordner = ablage(kennung)
            name = "%s-%s%s" % (
                datetime.datetime.now().strftime("%H%M%S"),
                aid or "ohne", endung)
            ziel = os.path.join(ordner, name)
            try:
                with open(ziel, "wb") as fh:
                    fh.write(nutz)
                dateien = sorted(os.listdir(ordner))
                for altd in dateien[:-BEHALTEN]:
                    try:
                        os.remove(os.path.join(ordner, altd))
                    except OSError:
                        pass
            except OSError as e:
                melde("Ablage fehlgeschlagen: %s" % e)
            melde("ERGEBNIS <- %s: id=%s status=%s %d Oktett -> %s"
                  % (kennung, aid, status, len(nutz), ziel))
            return b""

        if wort == "tschuess":
            with _sperre:
                g.gesehen = jetzt()
                g.tschuess = True
            return b""
        return self._weg("unbekannt: " + wort)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True
    verwalter = None
    # RUNDE MERGE-11: Draht-Kennung -> welches Geraet dahintersteckt.
    draehte = {}


def main():
    global _wurzel
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8090)
    ap.add_argument("--bind", default="127.0.0.1")
    ap.add_argument("--wurzel", default="/srv/bruecke")
    a = ap.parse_args()
    _wurzel = a.wurzel
    os.makedirs(os.path.join(_wurzel, "geraete"), exist_ok=True)

    # Der Verwalterschluessel. Entsteht beim ersten Start, liegt mit
    # 0600 da, und ohne ihn kann niemand Auftraege stellen.
    pfad = os.path.join(_wurzel, "verwalter.key")
    if not os.path.exists(pfad):
        with open(pfad, "w") as f:
            f.write(secrets.token_hex(32))
        os.chmod(pfad, 0o600)
    with open(pfad) as f:
        Server.verwalter = f.read().strip()

    zustand_lesen()
    status_lesen()
    threading.Thread(target=waechter, daemon=True).start()
    with Server((a.bind, a.port), Griff) as s:
        melde("Bruecke horcht auf %s:%d (Wurzel %s, Ed25519 %s)"
              % (a.bind, a.port, _wurzel,
                 "ja" if HAT_ED25519 else "nein -- HMAC-Rueckfall"))
        s.serve_forever()


if __name__ == "__main__":
    main()
