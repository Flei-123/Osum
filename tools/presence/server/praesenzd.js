// lib/praesenzd.js -- RUNDE PRAESENZ: DER KONTODIENST FUER FREUNDE,
// PRAESENZ UND 1:1-CHAT.
//
// =====================================================================
// WAS DAS IST
// =====================================================================
//
// Justins Wunsch, woertlich: "solche Dienste wie Freunde oder
// Chat-System waeren schon auch cool, wo man auch sieht, was ein Freund
// gerade macht -- aber halt im OS integriert, mit dem OS-Konto".
//
// Die OS-Seite (`kernel/user/praesenz.fi`) haelt den eigenen Status und
// verteilt ihn LOKAL am Systembus. Diese Datei ist die andere Haelfte:
// sie kennt den Freundschaftsgraphen, schiebt Statusaenderungen an die
// Freunde, die sie sehen duerfen, und traegt die Chatnachrichten --
// OHNE sie lesen zu koennen.
//
// =====================================================================
// WARUM EIN ZWEITER DIENST UND KEIN UMBAU VON osumbridge.js
// =====================================================================
//
// `lib/osumbridge.js` ist die GERAETEBRUECKE: sie meldet ein
// Osum-Geraet als Geraet in der Registry an, damit remote_shell &
// Freunde damit arbeiten. Das ist eine Sache zwischen JUSTIN und
// SEINEM Rechner.
//
// Praesenz und Chat sind eine Sache zwischen ZWEI MENSCHEN. Das ist ein
// anderer Vertrauensraum, ein anderer Lebenszyklus (ein Chat ueberlebt
// das Abmelden eines Geraets) und ein anderes Fehlerbild. Deshalb ein
// eigener Eingang -- dieselbe Begruendung, die osumbridge.js selbst fuer
// seinen eigenen Port gibt ("damit ein Fehler darin nicht im Chat-Server
// steht"), und deshalb wird an jener Datei KEINE Zeile geaendert.
//
// Gemeinsam ist die IDENTITAET: beide erkennen ein Geraet an seinem
// Ed25519-Schluessel aus demselben Koppelbuch (data/osum_devices.json).
// Wer dort steht, hat sein Geraet am Cockpit gekoppelt und gehoert zu
// einem JARVIS-Konto. Damit ist die Frage "wer bist du" schon
// beantwortet, bevor diese Datei anfaengt.
//
// =====================================================================
// DAS WICHTIGSTE: DER SERVER KANN DEN CHAT NICHT LESEN
// =====================================================================
//
// Das ist aus RUNDE SYNC uebernommen ("der Abgleich, den der Server
// nicht mitlesen kann") und hier genauso gemeint. Konkret:
//
//   * Eine Chatnachricht kommt als CHIFFRAT an. Dieser Server sieht
//     `von`, `an`, eine Laenge, einen Zeitstempel und einen Block
//     Oktette, die fuer ihn Rauschen sind.
//   * Er hat KEINEN Schluessel und bekommt nie einen. Die Schluessel
//     entstehen aus X25519 zwischen den GERAETEN; der oeffentliche Teil
//     steht im Koppelbuch, der private verlaesst das Geraet nicht (das
//     ist dasselbe Muster wie `jsig` in RUNDE BRIDGE: der private
//     Schluessel liegt nicht im Prozess am Netz).
//   * Das Postfach fuer Offline-Zustellung speichert denselben Block
//     unveraendert. Ein Postfach, das entschluesseln koennte, waere ein
//     Server, der mitliest, mit extra Schritten.
//
// WAS ER TROTZDEM SIEHT, und das gehoert genannt statt verschwiegen --
// dieselbe Ehrlichkeit wie Abschnitt 4 von RUNDE SYNC: WER mit WEM,
// WANN, WIE OFT und WIE VIEL. Verkehrsanalyse bleibt moeglich. Diese
// Runde tut nichts dagegen und behauptet auch nicht, es zu tun.
//
// =====================================================================
// DAS PROTOKOLL
// =====================================================================
//
// Dasselbe Zeilenprotokoll wie die Geraetebruecke, weil Osums Seite es
// schon kann und ein zweites Format zwei Fehlerquellen waeren: EINE
// Zeile, deren LETZTES Feld die Laenge der Nutzlast ist, danach genau so
// viele Oktette. Alles mit moeglichen Leerzeichen steht als Hex.
//
//   Geraet -> Server                     Server -> Geraet
//     hallo <pubhex> 0                     forderung <noncehex> 0
//     beweis <sighex> 0                    willkommen <uid> 0
//     status <zustandhex> 0                praesenz <freund> <zhex> 0
//     freunde 0                            freundliste <n> <len>
//     anfrage <namehex> 0                  anfrage-von <namehex> 0
//     annehmen <namehex> 0                 freund-neu <namehex> 0
//     entfernen <namehex> 0                post <von> <len>
//     senden <an> <len>                    zugestellt <id> 0
//     abholen 0                            leer 0
//
// `status` traegt denselben 64-Oktett-Rahmen wie der Bus (Art, Zustand,
// App-Laenge, Text-Laenge, App, Text) -- dasselbe Modell auf beiden
// Seiten, damit niemand zwei Bedeutungen von "abwesend" pflegen muss.

import { createServer } from 'node:tls'
import { randomBytes } from 'node:crypto'
import fs from 'node:fs'
import { Zeilenleser, pruefeBeweis } from './osumbridge.js'

const hex = (s) => Buffer.from(String(s), 'utf8').toString('hex')
const unhex = (h) => Buffer.from(String(h || ''), 'hex')

// =====================================================================
// DER FREUNDSCHAFTSGRAPH
// =====================================================================
//
// Eine Freundschaft ist BEIDSEITIG und wird als ZWEI Eintraege
// gefuehrt, nicht als ein Paar. Der Grund ist die Frage, die beim
// Zustellen gestellt wird: "darf B den Status von A sehen?" -- die
// beantwortet ein Eintrag unter A, ohne dass irgendwo eine
// Paar-Ordnung sortiert werden muss. Ein Paar (min,max) waere kuerzer
// und beim Lesen jedes Mal eine Denkaufgabe.
//
// Eine ANFRAGE ist einseitig: sie steht nur beim Empfaenger. Erst das
// Annehmen legt die zwei Eintraege an. Damit kann niemand durch
// Anfragen erfahren, ob es ein Konto gibt -- die Antwort ist immer
// dieselbe.
export class Freundesbuch {
  constructor(datei) {
    this.datei = datei
    this.d = { freunde: {}, anfragen: {}, post: {} }
    try {
      const roh = JSON.parse(fs.readFileSync(datei, 'utf8'))
      this.d = {
        freunde: roh.freunde || {},
        anfragen: roh.anfragen || {},
        post: roh.post || {},
      }
    } catch { /* neue Anlage */ }
  }

  sichern() {
    try {
      fs.writeFileSync(this.datei, JSON.stringify(this.d, null, 2))
    } catch { /* eine nicht schreibbare Datei darf den Dienst nicht toeten */ }
  }

  liste(uid) {
    return this.d.freunde[uid] ? [...this.d.freunde[uid]] : []
  }

  sindFreunde(a, b) {
    return !!(this.d.freunde[a] && this.d.freunde[a].includes(b))
  }

  offeneAnfragen(uid) {
    return this.d.anfragen[uid] ? [...this.d.anfragen[uid]] : []
  }

  // Anfragen sind einseitig und still: die Antwort verraet nicht, ob
  // das Ziel existiert.
  anfragen(von, an) {
    if (!von || !an || von === an) return false
    if (this.sindFreunde(von, an)) return false
    // Hat die Gegenseite MICH schon angefragt, ist das Annehmen.
    if ((this.d.anfragen[von] || []).includes(an)) {
      return this.annehmen(von, an)
    }
    const l = this.d.anfragen[an] || (this.d.anfragen[an] = [])
    if (!l.includes(von)) l.push(von)
    this.sichern()
    return true
  }

  annehmen(uid, von) {
    const l = this.d.anfragen[uid] || []
    const i = l.indexOf(von)
    if (i < 0) return false
    l.splice(i, 1)
    const a = this.d.freunde[uid] || (this.d.freunde[uid] = [])
    const b = this.d.freunde[von] || (this.d.freunde[von] = [])
    if (!a.includes(von)) a.push(von)
    if (!b.includes(uid)) b.push(uid)
    this.sichern()
    return true
  }

  // Entfernen wirkt AUF BEIDEN SEITEN. Eine halbe Freundschaft waere
  // ein Zustand, in dem einer noch sieht und der andere nicht mehr --
  // und das waere die unangenehmste Variante von beiden.
  entfernen(uid, wen) {
    let was = false
    for (const [x, y] of [[uid, wen], [wen, uid]]) {
      const l = this.d.freunde[x]
      if (!l) continue
      const i = l.indexOf(y)
      if (i >= 0) { l.splice(i, 1); was = true }
    }
    if (was) this.sichern()
    return was
  }

  // ---------------------------------------------------------- Postfach
  //
  // Ein Postfach haelt CHIFFRAT. Der Server legt ab, was er bekommt,
  // und gibt es weiter, wenn der Empfaenger wiederkommt.
  //
  // Zwei Grenzen, damit ein Postfach kein Speicherleck mit Adresse ist:
  // hoechstens POST_MAX Nachrichten je Empfaenger, und wer voll ist,
  // verliert die AELTESTE. Die Alternative (die neueste ablehnen) haelt
  // ein volles Postfach fuer immer voll.
  ablegen(an, von, chiffrat, POST_MAX = 500) {
    const l = this.d.post[an] || (this.d.post[an] = [])
    l.push({ von, at: Date.now(), c: chiffrat.toString('base64') })
    while (l.length > POST_MAX) l.shift()
    this.sichern()
    return l.length
  }

  abholen(an) {
    const l = this.d.post[an] || []
    this.d.post[an] = []
    if (l.length) this.sichern()
    return l
  }

  postAnzahl(an) {
    return (this.d.post[an] || []).length
  }
}

// =====================================================================
// DER LAUSCHER
// =====================================================================

export function startePraesenzDienst(opt) {
  const {
    port = 8444,
    cert,
    key,
    buch,          // Koppelbuch aus osumbridge.js: pubhex -> { uid, name }
    freunde,       // Freundesbuch
    log = () => {},
  } = opt

  // uid -> Set(Verbindung). Ein Mensch hat mehrere Geraete, und alle
  // sollen dieselbe Post und dieselbe Praesenz sehen.
  const offen = new Map()
  // uid -> letzter Statusrahmen (64 Oktette). Nur im Speicher: ein
  // Status ist eine Aussage ueber JETZT, und nach einem Neustart ist
  // "was hat er vor drei Tagen gemacht" keine Antwort, sondern Muell.
  const status = new Map()

  const einhaengen = (uid, v) => {
    let s = offen.get(uid)
    if (!s) { s = new Set(); offen.set(uid, s) }
    s.add(v)
  }
  const aushaengen = (uid, v) => {
    const s = offen.get(uid)
    if (!s) return
    s.delete(v)
    if (!s.size) offen.delete(uid)
  }

  // Rueckgabe: ob wirklich geschrieben wurde. DAS IST NICHT KOSMETIK.
  // Ein Fehler dieser Runde, den der Pruefstand gefunden hat: eine
  // Verbindung, die gerade abreisst, steht noch in `offen`, weil
  // 'close' erst im naechsten Durchlauf der Ereignisschleife kommt.
  // Wer den Rueckgabewert nicht ansieht, zaehlt eine Zustellung an
  // einen toten Draht als Zustellung -- und legt die Nachricht dann
  // NICHT ins Postfach. Sie ist damit weg, und zwar still.
  const zeile = (sock, txt, nutz = null) => {
    // `writable` ist false, sobald end()/destroy() gelaufen ist. Das
    // ist die Frage "kommt das noch an", und sie wird hier gestellt,
    // bevor geschrieben wird.
    if (!sock || !sock.writable || sock.destroyed) return false
    try {
      sock.write(txt + ' ' + (nutz ? nutz.length : 0) + '\n')
      if (nutz && nutz.length) sock.write(nutz)
      return true
    } catch {
      return false
    }
  }

  // Einen Status an alle Freunde schieben, die ihn sehen DUERFEN.
  // Die Rechtefrage wird hier je Empfaenger EINZELN gestellt -- genau
  // wie der Systembus es beim Veroeffentlichen tut.
  const praesenzSchieben = (uid, rahmen) => {
    let n = 0
    for (const f of freunde.liste(uid)) {
      const s = offen.get(f)
      if (!s) continue
      for (const v of s) {
        zeile(v.sock, 'praesenz ' + hex(uid) + ' ' + rahmen.toString('hex'))
        n++
      }
    }
    return n
  }

  // Beim Anmelden: was machen meine Freunde gerade?
  const praesenzHolen = (uid, sock) => {
    for (const f of freunde.liste(uid)) {
      const r = status.get(f)
      if (r) zeile(sock, 'praesenz ' + hex(f) + ' ' + r.toString('hex'))
    }
  }

  const srv = createServer(
    {
      cert: fs.readFileSync(cert),
      key: fs.readFileSync(key),
      minVersion: 'TLSv1.3',
      // DIESELBEN ZWEI VERFAHREN WIE DIE GERAETEBRUECKE, und aus
      // demselben Grund: Osums TLS (vendor/firn/lib/tls/tls.fi) kann
      // genau diese zwei. Eine dritte Angabe hier waere eine Zeile, die
      // nie zutrifft, und beim naechsten Lesen eine falsche Auskunft.
      ciphers: 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384',
    },
    (sock) => {
      const v = { sock, uid: null, name: null, nonce: null, pub: null }
      const leser = new Zeilenleser()
      sock.setTimeout(10 * 60 * 1000)

      leser.onNachricht = (felder, nutz) => {
        const op = felder[0]

        // --- Anmeldung: Forderung und Beweis ------------------------
        if (op === 'hallo') {
          v.pub = String(felder[1] || '')
          v.nonce = randomBytes(32)
          zeile(sock, 'forderung ' + v.nonce.toString('hex'))
          return
        }

        if (op === 'beweis') {
          const e = buch.finde(v.pub)
          const sig = unhex(felder[1])
          // Erst das Geraet im Buch, dann die Unterschrift. Fehlt das
          // Geraet, wird gar nicht erst gerechnet -- und die Antwort
          // ist dieselbe wie bei falscher Unterschrift.
          if (!e || !v.nonce || !pruefeBeweis(unhex(v.pub), v.nonce, sig)) {
            zeile(sock, 'nein')
            try { sock.end() } catch { /* */ }
            return
          }
          v.uid = e.uid
          v.name = e.name
          einhaengen(v.uid, v)
          zeile(sock, 'willkommen ' + hex(v.uid))
          praesenzHolen(v.uid, sock)
          // Wartende Post sofort melden, nicht erst auf 'abholen'.
          const n = freunde.postAnzahl(v.uid)
          if (n) zeile(sock, 'postfach ' + n)
          log(`praesenzd: ${v.name} (${v.uid}) angemeldet`)
          return
        }

        // Ab hier: nur mit Anmeldung.
        if (!v.uid) { zeile(sock, 'nein'); return }

        // --- Praesenz ----------------------------------------------
        if (op === 'status') {
          const rahmen = unhex(felder[1])
          if (rahmen.length !== 64) { zeile(sock, 'nein'); return }
          status.set(v.uid, rahmen)
          const n = praesenzSchieben(v.uid, rahmen)
          zeile(sock, 'verteilt ' + n)
          return
        }

        // --- Freunde ------------------------------------------------
        if (op === 'freunde') {
          const l = freunde.liste(v.uid)
          const a = freunde.offeneAnfragen(v.uid)
          const nutzlast = Buffer.from(JSON.stringify({
            freunde: l.map((f) => ({
              uid: f,
              online: offen.has(f),
              status: status.get(f) ? status.get(f).toString('hex') : null,
            })),
            anfragen: a,
          }), 'utf8')
          zeile(sock, 'freundliste', nutzlast)
          return
        }

        if (op === 'anfrage') {
          const an = unhex(felder[1]).toString('utf8')
          freunde.anfragen(v.uid, an)
          // IMMER dieselbe Antwort. Ob es das Konto gibt, ob schon eine
          // Anfrage lief, ob geblockt wurde -- der Anfragende erfaehrt
          // es nicht, sonst ist das hier eine Kontoauskunft.
          zeile(sock, 'gesendet')
          for (const s of offen.get(an) || []) {
            zeile(s.sock, 'anfrage-von ' + hex(v.uid))
          }
          return
        }

        if (op === 'annehmen') {
          const von = unhex(felder[1]).toString('utf8')
          if (!freunde.annehmen(v.uid, von)) { zeile(sock, 'nein'); return }
          zeile(sock, 'freund-neu ' + hex(von))
          for (const s of offen.get(von) || []) {
            zeile(s.sock, 'freund-neu ' + hex(v.uid))
          }
          // Beide sehen einander ab jetzt -- also gleich den Stand.
          const meiner = status.get(v.uid)
          if (meiner) {
            for (const s of offen.get(von) || []) {
              zeile(s.sock, 'praesenz ' + hex(v.uid) + ' ' + meiner.toString('hex'))
            }
          }
          const seiner = status.get(von)
          if (seiner) {
            zeile(sock, 'praesenz ' + hex(von) + ' ' + seiner.toString('hex'))
          }
          return
        }

        if (op === 'entfernen') {
          const wen = unhex(felder[1]).toString('utf8')
          freunde.entfernen(v.uid, wen)
          zeile(sock, 'entfernt')
          // Der andere erfaehrt es, denn sein Fenster zeigt sonst einen
          // Status, den er nicht mehr bekommt -- und das sieht aus wie
          // "der ist seit Tagen abwesend" statt "wir sind keine
          // Freunde mehr".
          for (const s of offen.get(wen) || []) {
            zeile(s.sock, 'entfernt-von ' + hex(v.uid))
          }
          return
        }

        // --- Chat ---------------------------------------------------
        //
        // `nutz` ist CHIFFRAT. Diese Datei liest es nicht, prueft es
        // nicht und kann es nicht -- sie reicht es weiter oder legt es
        // ins Postfach.
        if (op === 'senden') {
          const an = unhex(felder[1]).toString('utf8')
          if (!freunde.sindFreunde(v.uid, an)) {
            // Kein Chat ohne Freundschaft. Sonst ist ein Chatdienst ein
            // Weg, jedem Fremden etwas zu schicken.
            zeile(sock, 'nein')
            return
          }
          const s = offen.get(an)
          let zugestellt = 0
          if (s) {
            for (const ziel of s) {
              // NUR eine Zustellung, die wirklich auf den Draht ging,
              // zaehlt. Sonst landet die Nachricht weder beim
              // Empfaenger noch im Postfach.
              if (zeile(ziel.sock, 'post ' + hex(v.uid), nutz)) zugestellt++
            }
          }
          // AUCH bei Zustellung ins Postfach, wenn NIEMAND online war.
          if (!zugestellt) freunde.ablegen(an, v.uid, nutz)
          zeile(sock, 'zugestellt ' + zugestellt)
          return
        }

        if (op === 'abholen') {
          const l = freunde.abholen(v.uid)
          for (const m of l) {
            zeile(sock, 'post ' + hex(m.von), Buffer.from(m.c, 'base64'))
          }
          zeile(sock, 'leer ' + l.length)
          return
        }

        zeile(sock, 'unbekannt')
      }

      sock.on('data', (d) => leser.schub(d))
      sock.on('timeout', () => { try { sock.end() } catch { /* */ } })
      sock.on('error', () => { /* ein Abriss ist kein Ereignis */ })
      sock.on('close', () => {
        if (!v.uid) return
        aushaengen(v.uid, v)
        // Das letzte Geraet geht -> die Freunde sehen "offline". Ein
        // Status, der nach dem Abriss stehen bliebe, waere eine Luege
        // mit Zeitstempel.
        if (!offen.has(v.uid)) {
          status.delete(v.uid)
          const weg = Buffer.alloc(64)
          weg[1] = 1 // Z_WEG, derselbe Rahmen wie am Bus
          praesenzSchieben(v.uid, weg)
        }
        log(`praesenzd: ${v.name || '?'} getrennt`)
      })
    },
  )

  srv.on('error', (e) => log('praesenzd: ' + (e?.message || e)))
  srv.listen(port, opt.host || '0.0.0.0', () => {
    log(`praesenzd: lauscht auf ${port}`)
  })
  return srv
}
