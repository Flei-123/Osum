#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/standby/lauf.py -- EIN S3-Lauf, von aussen gesteuert.
#
# WARUM PYTHON UND QMP UND NICHT `socat` AUF DEN HMP-MONITOR. Der
# Menschenmonitor gibt kein Ende-Zeichen aus; jeder Leser muss raten,
# wann eine Antwort fertig ist, und nach `system_wakeup` blieb genau
# dieses Raten haengen (gemessen: die zweite Abfrage antwortet nie).
# QMP ist zeilenweises JSON mit einer Antwort je Befehl -- da gibt es
# nichts zu raten.
#
# Aufruf:
#   lauf.py --abbild PFAD --anhang "standby s3go" [--wecken-nach 2.0]
#           [--uhr-vor SEKUNDEN] [--warten 12] [--aus DATEI]
#
# Rueckgabe: 0, wenn die Maschine geschlafen HAT und wieder aufgewacht
# ist; sonst ungleich null. Auf der Standardausgabe steht die serielle
# Ausgabe ab dem Einschlafen.
import argparse
import json
import os
import socket
import subprocess
import sys
import tempfile
import time


class Qmp:
    """Der kleinste QMP-Sprecher, der fuer diese Runde reicht."""

    def __init__(self, pfad, frist=8.0):
        ende = time.time() + frist
        self.s = None
        self.ereignisse = []
        while time.time() < ende:
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.connect(pfad)
                self.s = s
                break
            except OSError:
                time.sleep(0.05)
        if self.s is None:
            raise RuntimeError("QMP nicht erreichbar: " + pfad)
        self.s.settimeout(frist)
        self.puffer = b""
        self.zeile()                      # die Begruessung
        self.befehl("qmp_capabilities")

    def zeile(self):
        while b"\n" not in self.puffer:
            teil = self.s.recv(65536)
            if not teil:
                raise RuntimeError("QMP hat aufgelegt")
            self.puffer += teil
        z, self.puffer = self.puffer.split(b"\n", 1)
        return json.loads(z.decode("utf-8"))

    def befehl(self, name, **args):
        p = {"execute": name}
        if args:
            p["arguments"] = args
        self.s.sendall((json.dumps(p) + "\n").encode("utf-8"))
        while True:
            a = self.zeile()
            if "return" in a or "error" in a:
                return a
            # Alles andere ist ein Ereignis (SUSPEND, WAKEUP, RESET) und
            # wird gesammelt, damit der Aufrufer es sehen kann.
            self.ereignisse.append(a)

    def status(self):
        # Ein Zeitablauf ist hier KEIN Fehler: solange der Gast unter TCG
        # in einer engen Ein-/Ausgabeschleife steht, kommt die
        # Hauptschleife von QEMU kaum zum Zug und antwortet spaeter.
        try:
            a = self.befehl("query-status")
        except (socket.timeout, TimeoutError, OSError, RuntimeError):
            return None
        return a.get("return", {}).get("status")


def zeitstempel(vor):
    t = time.gmtime(time.time() + vor)
    return time.strftime("%Y-%m-%dT%H:%M:%S", t)


def haupt():
    p = argparse.ArgumentParser()
    p.add_argument("--abbild", required=True)
    p.add_argument("--anhang", default="standby s3go")
    p.add_argument("--wecken-nach", dest="wecken_nach", type=float,
                   default=2.0,
                   help="Sekunden nach dem Einschlafen bis system_wakeup")
    p.add_argument("--nicht-wecken", dest="nicht_wecken",
                   action="store_true")
    p.add_argument("--warten", type=float, default=12.0,
                   help="Sekunden Geduld nach dem Wecken")
    p.add_argument("--uhr-vor", dest="uhr_vor", type=float, default=0.0,
                   help="die Gastuhr um so viele Sekunden vorstellen")
    p.add_argument("--runden", type=int, default=1,
                   help="Reihenlauf: so oft von aussen wecken")
    p.add_argument("--speicher", default="128")
    p.add_argument("--platte", default="")
    p.add_argument("--marke", default="standby: fertig",
                   help="Wort im seriellen Strom, das das Ende des Aufwachpfades anzeigt")
    p.add_argument("--aus", default="")
    p.add_argument("--qemu", default="qemu-system-x86_64")
    a = p.parse_args()

    arb = tempfile.mkdtemp(prefix="standby-")
    ser = os.path.join(arb, "seriell.txt")
    qmp = os.path.join(arb, "qmp.sock")

    befehl = [a.qemu, "-accel", "tcg", "-kernel", a.abbild,
              "-m", a.speicher, "-append", a.anhang,
              "-serial", "file:" + ser, "-display", "none", "-no-reboot",
              "-qmp", "unix:%s,server,nowait" % qmp,
              "-global", "PIIX4_PM.disable_s3=0"]
    if a.uhr_vor:
        befehl += ["-rtc", "base=" + zeitstempel(a.uhr_vor)]
    if a.platte:
        # IDE, weil das der Anschluss ist, den `osum` von sich aus
        # findet (dieselbe Zeile wie in tools/ofs3/run.sh).
        befehl += ["-drive",
                   "file=%s,format=raw,if=ide,index=0" % a.platte]

    q = subprocess.Popen(befehl, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL)
    geschlafen = False
    geweckt = False
    zustand = "?"
    t_ein = 0.0
    t_wach = 0.0
    try:
        m = Qmp(qmp)
        ende = time.time() + 30
        while time.time() < ende:
            if m.status() == "suspended":
                geschlafen = True
                t_ein = time.time()
                break
            time.sleep(0.05)
        if a.runden > 1:
            # REIHENLAUF: der Kern schlaeft `runden` mal hintereinander
            # (`s3loop`), und hier wird jedes Mal von aussen geweckt.
            # Gezaehlt wird, wie oft die Maschine wirklich wieder
            # angelaufen ist -- das ist die Zahl, die im Bericht steht.
            n_ein = 0
            n_auf = 0
            ende = time.time() + a.warten
            while time.time() < ende:
                z = m.status()
                if z == "suspended":
                    n_ein += 1
                    time.sleep(a.wecken_nach)
                    m.befehl("system_wakeup")
                    t0 = time.time()
                    while time.time() < t0 + 20:
                        if m.status() == "running":
                            n_auf += 1
                            break
                        time.sleep(0.02)
                else:
                    time.sleep(0.02)
                if os.path.exists(ser):
                    if b"standby: reihe" in open(ser, "rb").read():
                        break
            geschlafen = n_ein > 0
            geweckt = n_auf > 0
            print("== reihe: eingeschlafen=%d geweckt=%d" % (n_ein, n_auf))
        elif geschlafen and not a.nicht_wecken:
            time.sleep(a.wecken_nach)
            m.befehl("system_wakeup")
            t0 = time.time()
            ende = time.time() + a.warten
            while time.time() < ende:
                if m.status() == "running":
                    geweckt = True
                    t_wach = time.time() - t0
                    break
                time.sleep(0.02)
            # Nicht blind warten, sondern auf ein Wort aus dem Kern:
            # der Aufwachpfad ist unter TCG mal in einer und mal in
            # acht Sekunden durch, und ein fester Wert misst dann den
            # Wirt und nicht das System.
            ende = time.time() + a.warten
            while time.time() < ende:
                if os.path.exists(ser):
                    d = open(ser, "rb").read()
                    if a.marke.encode("utf-8") in d:
                        break
                time.sleep(0.1)
        zustand = m.status() or "?"
    finally:
        q.terminate()
        try:
            q.wait(timeout=10)
        except subprocess.TimeoutExpired:
            q.kill()

    text = ""
    if os.path.exists(ser):
        text = open(ser, "rb").read().decode("utf-8", "replace")
    if a.aus:
        open(a.aus, "w", encoding="utf-8").write(text)
    marke = text.find("einschlafen")
    print("== geschlafen=%s geweckt=%s status=%s wirt_wach_ms=%d" % (
        geschlafen, geweckt, zustand, int(t_wach * 1000)))
    print("== serielle Ausgabe ab dem Schlaf:")
    print(text[marke:] if marke >= 0 else text[-2000:])
    if not geschlafen:
        return 2
    if not a.nicht_wecken and not geweckt:
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(haupt())
