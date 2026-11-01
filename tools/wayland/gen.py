#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

import sys
import xml.etree.ElementTree as ET

WAYLAND_XML = "/usr/share/wayland/wayland.xml"
XDG_XML = "/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml"
VIEWPORTER_XML = "/usr/share/wayland-protocols/stable/viewporter/viewporter.xml"
DECORATION_XML = "/usr/share/wayland-protocols/unstable/xdg-decoration/xdg-decoration-unstable-v1.xml"

LIMIT = [
    "wl_display", "wl_registry", "wl_callback", "wl_compositor",
    "wl_shm", "wl_shm_pool", "wl_buffer", "wl_surface",
    "wl_seat", "wl_keyboard", "wl_pointer", "wl_output", "wl_region",
    "xdg_wm_base", "xdg_surface", "xdg_toplevel",
    "wl_data_device_manager", "wl_data_device", "wl_data_source",
    "wl_data_offer",
    "wl_subcompositor", "wl_subsurface",
    "wp_viewporter", "wp_viewport",
    "zxdg_decoration_manager_v1", "zxdg_toplevel_decoration_v1",
]

VERSION = {
    "wl_compositor": 4,
    "wl_shm": 1,
    "wl_seat": 5,
    "wl_data_device_manager": 3,
    "wl_output": 2,
    "wl_subcompositor": 1,
    "xdg_wm_base": 3,
    "wp_viewporter": 1,
    "zxdg_decoration_manager_v1": 1,
}

ARGCODE = {
    "int": 1, "uint": 2, "fixed": 3, "string": 4, "object": 5,
    "new_id": 6, "array": 7, "fd": 8,
}


def firn_name(s):
    return s.upper()


def load(path):
    return ET.parse(path).getroot()


def main():
    out = []
    w = out.append

    w("// SPDX-License-Identifier: GPL-2.0-only")
    w("// kernel/user/wlproto.fi -- ERZEUGT von tools/wayland/gen.py.")
    w("//")
    w("// NICHT VON HAND AENDERN. Die Quelle sind die offiziellen")
    w("// Protokolldateien:")
    w("//   %s" % WAYLAND_XML)
    w("//   %s" % XDG_XML)
    w("//   %s" % VIEWPORTER_XML)
    w("//   %s" % DECORATION_XML)
    w("//")
    w("// Neu erzeugen:  ./tools/wayland/gen.py > kernel/user/wlproto.fi")
    w("//")
    w("// Was hier steht, sind DATEN und keine Logik: die Nummern der")
    w("// Schnittstellen, die Signaturen der Anfragen (woran der Server")
    w("// die Laenge eines Pakets misst) und die Opcodes der Ereignisse,")
    w("// die dieser Server wirklich schickt. Die Logik steht in")
    w("// kernel/user/wayd.fi.")
    w("")
    w("profile kernel")
    w("")

    roots = [load(WAYLAND_XML), load(XDG_XML), load(VIEWPORTER_XML), load(DECORATION_XML)]
    ifaces = {}
    for r in roots:
        for i in r.findall("interface"):
            ifaces[i.get("name")] = i

    missing = [n for n in LIMIT if n not in ifaces]
    if missing:
        sys.stderr.write("fehlende Schnittstellen: %s\n" % missing)
        return 1

    exports = []
    body = []

    body.append("// ------------------------------------- die Schnittstellen")
    body.append("//")
    body.append("// Unsere eigene Nummerierung. Im Protokoll kommen")
    body.append("// Schnittstellen als ZEICHENKETTE vor (wl_registry.bind);")
    body.append("// der Server loest sie einmal auf und rechnet danach mit")
    body.append("// diesen Zahlen.")
    for n, name in enumerate(LIMIT):
        c = "IF_" + firn_name(name)
        body.append("const %s: u64 = %d" % (c, n))
        exports.append(c)
    body.append("const IF_COUNT: u64 = %d" % len(LIMIT))
    body.append("const IF_NONE: u64 = %d" % len(LIMIT))
    exports += ["IF_COUNT", "IF_NONE"]
    body.append("")

    body.append("// Welche Fassung dieser Server anbietet. Mehr zu")
    body.append("// behaupten als gebaut ist, ist die eine Luege, die ein")
    body.append("// Client nicht ueberlebt.")
    body.append("fn version_of(iface: u64) -> u64 {")
    for name in LIMIT:
        if name in VERSION:
            body.append("    if iface == IF_%s {" % firn_name(name))
            body.append("        return %d" % VERSION[name])
            body.append("    }")
    body.append("    return 1")
    body.append("}")
    exports.append("version_of")
    body.append("")

    body.append("// Der NAME einer Schnittstelle, wie er im Protokoll")
    body.append("// steht. `wl_registry.global` schickt ihn, und")
    body.append("// `wl_registry.bind` bringt ihn zurueck.")
    body.append("fn name_len(iface: u64) -> u64 {")
    for name in LIMIT:
        body.append("    if iface == IF_%s {" % firn_name(name))
        body.append("        return %d" % len(name))
        body.append("    }")
    body.append("    return 0")
    body.append("}")
    exports.append("name_len")
    body.append("")

    body.append("// Das i-te Oktett des Namens. Eine Tabelle aus Zeichen-")
    body.append("// ketten waere in Firn ein Feld von Zeigern; so ist es")
    body.append("// eine reine Rechnung und braucht keinen Speicher.")
    body.append("fn name_at(iface: u64, i: u64) -> u64 {")
    for name in LIMIT:
        body.append("    if iface == IF_%s {" % firn_name(name))
        for k, ch in enumerate(name):
            body.append("        if i == %d {" % k)
            body.append("            return %d // '%s'" % (ord(ch), ch))
            body.append("        }")
        body.append("        return 0")
        body.append("    }")
    body.append("    return 0")
    body.append("}")
    exports.append("name_at")
    body.append("")

    body.append("// ----------------------------------------- die Anfragen")
    body.append("//")
    body.append("// Je Schnittstelle und Opcode: wieviele Argumente, und")
    body.append("// ob eines davon ein DESKRIPTOR ist (dann kommt es nicht")
    body.append("// im Strom, sondern als SCM_RIGHTS daneben).")
    for name in LIMIT:
        el = ifaces[name]
        for op, req in enumerate(el.findall("request")):
            c = "RQ_%s_%s" % (firn_name(name), firn_name(req.get("name")))
            body.append("const %s: u64 = %d" % (c, op))
            exports.append(c)
    body.append("")

    body.append("// Traegt diese Anfrage einen Deskriptor?")
    body.append("fn req_has_fd(iface: u64, op: u64) -> bool {")
    any_fd = False
    for name in LIMIT:
        el = ifaces[name]
        for op, req in enumerate(el.findall("request")):
            if any(a.get("type") == "fd" for a in req.findall("arg")):
                any_fd = True
                body.append("    if iface == IF_%s && op == %d {"
                            % (firn_name(name), op))
                body.append("        return true // %s.%s"
                            % (name, req.get("name")))
                body.append("    }")
    if not any_fd:
        body.append("    // keine")
    body.append("    return false")
    body.append("}")
    exports.append("req_has_fd")
    body.append("")

    body.append("// Wieviele Anfragen kennt diese Schnittstelle? Ein")
    body.append("// Opcode darueber ist ein Protokollfehler -- und genau")
    body.append("// das ist die Gegenprobe 'falsches Opcode-Paket'.")
    body.append("fn req_count(iface: u64) -> u64 {")
    for name in LIMIT:
        body.append("    if iface == IF_%s {" % firn_name(name))
        body.append("        return %d" % len(ifaces[name].findall("request")))
        body.append("    }")
    body.append("    return 0")
    body.append("}")
    exports.append("req_count")
    body.append("")

    body.append("// --------------------------------------- die Ereignisse")
    for name in LIMIT:
        el = ifaces[name]
        for op, ev in enumerate(el.findall("event")):
            c = "EV_%s_%s" % (firn_name(name), firn_name(ev.get("name")))
            body.append("const %s: u64 = %d" % (c, op))
            exports.append(c)
    body.append("")

    body.append("// ----------------------------------------- die Fehler")
    body.append("// wl_display.error nennt einen Code, und der Client")
    body.append("// druckt ihn. Falsche Zahlen hier heissen falsche")
    body.append("// Fehlermeldungen dort.")
    for name in LIMIT:
        el = ifaces[name]
        for en in el.findall("enum"):
            if en.get("name") != "error":
                continue
            for e in en.findall("entry"):
                c = "ERR_%s_%s" % (firn_name(name),
                                   firn_name(e.get("name")))
                body.append("const %s: u64 = %s" % (c, e.get("value")))
                exports.append(c)
    body.append("")

    w("export {")
    line = "   "
    for e in exports:
        if len(line) + len(e) + 2 > 76:
            w(line.rstrip())
            line = "   "
        line += " %s," % e
    w(line.rstrip().rstrip(","))
    w("}")
    w("")
    out.extend(body)

    sys.stdout.write("\n".join(out) + "\n")
    sys.stderr.write("wlproto.fi: %d Schnittstellen, %d Konstanten\n"
                     % (len(LIMIT), len(exports)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
