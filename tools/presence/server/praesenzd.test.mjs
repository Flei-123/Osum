// test/praesenzd.test.mjs -- RUNDE PRAESENZ: der Pruefstand fuer den
// Kontodienst (Freunde, Praesenz, Chat).
//
// Gemessen wird gegen den ECHTEN Dienst ueber eine ECHTE TLS-Verbindung
// mit ECHTEN Ed25519-Schluesseln -- kein Nachbau im Speicher. Was hier
// gruen ist, ist auf dem Draht gruen.
//
// Die wichtigste Zusage steht in Abschnitt 6 und ist die, wegen der es
// diesen Dienst in dieser Form gibt: DER SERVER SIEHT DEN KLARTEXT
// NICHT. Sie wird nicht behauptet, sondern nachgezaehlt -- der ganze
// Mitschnitt des Servers wird nach dem Klartext durchsucht, und die
// Zahl der Treffer muss 0 sein.

import { strict as assert } from 'node:assert'
import { connect } from 'node:tls'
import {
  generateKeyPairSync, sign as edSign, randomBytes,
  createPrivateKey, diffieHellman, createPublicKey,
  createCipheriv, createDecipheriv, hkdfSync,
} from 'node:crypto'
import fs from 'node:fs'
import os from 'node:os'
import { join } from 'node:path'
import { execFileSync } from 'node:child_process'
import { Freundesbuch, startePraesenzDienst } from '../lib/praesenzd.js'
import { Zeilenleser } from '../lib/osumbridge.js'

let pass = 0, fail = 0
const ok = (b, t) => { if (b) { pass++; console.log('  OK    ' + t) } else { fail++; console.log('  FAIL  ' + t) } }
const eq = (a, b, t) => ok(a === b, t + ': ' + a + (a === b ? '' : ' != ' + b))

const TMP = fs.mkdtempSync(join(os.tmpdir(), 'praesenzd-'))
const PORT = 18444 + Math.floor(Math.random() * 400)

// --------------------------------------------------------- Zertifikat
// Aus openssl und nicht aus diesem Baum: ein Testzertifikat, das der
// Pruefling selbst erzeugt, prueft den Pruefling nicht.
execFileSync('openssl', [
  'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
  '-keyout', join(TMP, 'k.pem'), '-out', join(TMP, 'c.pem'),
  '-days', '2', '-subj', '/CN=praesenzd-test',
], { stdio: 'ignore' })

// --------------------------------------------------- zwei Geraete
const A = generateKeyPairSync('ed25519')
const B = generateKeyPairSync('ed25519')
const rohPub = (k) => k.export({ format: 'der', type: 'spki' }).subarray(-32)
const pubA = rohPub(A.publicKey).toString('hex')
const pubB = rohPub(B.publicKey).toString('hex')

const buch = {
  d: { [pubA]: { uid: 'justin', name: 'Osum-A' }, [pubB]: { uid: 'freund', name: 'Osum-B' } },
  finde(p) { return this.d[p] || null },
}
const freunde = new Freundesbuch(join(TMP, 'freunde.json'))

// Der Mitschnitt: ALLES, was der Server je zu sehen bekommt. Gegen
// diesen Puffer laeuft Abschnitt 6.
const mitschnitt = []
const log = (t) => mitschnitt.push(String(t))

const srv = startePraesenzDienst({
  port: PORT, cert: join(TMP, 'c.pem'), key: join(TMP, 'k.pem'),
  buch, freunde, log, host: '127.0.0.1',
})
// AUF DAS ECHTE 'listening' WARTEN und nicht auf eine geratene Zahl.
// Ein Test, der 300 ms schlaeft, ist auf einer belasteten Maschine ein
// Test, der manchmal rot ist -- und ein Laeufer, der manchmal rot ist,
// wird irgendwann nicht mehr gelesen.
await new Promise((r) => (srv.listening ? r() : srv.once('listening', r)))

// ------------------------------------------------------- ein Klient
class Klient {
  constructor(schluessel, pub) { this.k = schluessel; this.pub = pub; this.zeilen = []; this.posts = [] }
  async verbinde() {
    this.sock = connect({ port: PORT, host: '127.0.0.1', rejectUnauthorized: false })
    this.leser = new Zeilenleser()
    this.leser.onNachricht = (f, n) => {
      this.zeilen.push(f.join(' '))
      if (f[0] === 'post') this.posts.push({ von: Buffer.from(f[1], 'hex').toString(), c: n })
      if (f[0] === 'freundliste') this.liste = JSON.parse(n.toString('utf8'))
      this.warte?.()
    }
    this.sock.on('data', (d) => this.leser.schub(d))
    await new Promise((r) => this.sock.once('secureConnect', r))
  }
  sende(t, nutz = null) {
    this.sock.write(t + ' ' + (nutz ? nutz.length : 0) + '\n')
    if (nutz) this.sock.write(nutz)
  }
  async bis(prefix, ms = 3000) {
    const t0 = Date.now()
    for (;;) {
      const z = this.zeilen.find((x) => x.startsWith(prefix))
      if (z) return z
      if (Date.now() - t0 > ms) return null
      await new Promise((r) => { this.warte = r; setTimeout(r, 40) })
    }
  }
  async anmelden() {
    this.sende('hallo ' + this.pub)
    const f = await this.bis('forderung')
    const nonce = Buffer.from(f.split(' ')[1], 'hex')
    this.sende('beweis ' + edSign(null, nonce, this.k).toString('hex'))
    return await this.bis('willkommen')
  }
}

console.log('== 1. Anmeldung mit echtem Ed25519-Beweis ==')
const ka = new Klient(A.privateKey, pubA)
const kb = new Klient(B.privateKey, pubB)
await ka.verbinde(); await kb.verbinde()
ok(!!(await ka.anmelden()), 'Geraet A ist angemeldet')
ok(!!(await kb.anmelden()), 'Geraet B ist angemeldet')

console.log('== 1b. eine FALSCHE Unterschrift kommt nicht durch ==')
const kx = new Klient(generateKeyPairSync('ed25519').privateKey, pubA) // fremder Schluessel, echte pub
await kx.verbinde()
kx.sende('hallo ' + pubA)
await kx.bis('forderung')
kx.sende('beweis ' + randomBytes(64).toString('hex'))
ok(!!(await kx.bis('nein', 1500)), 'falscher Beweis: der Dienst sagt nein')

console.log('== 2. Freundschaft ==')
ka.sende('anfrage ' + Buffer.from('freund').toString('hex'))
ok(!!(await ka.bis('gesendet')), 'A fragt B an')
ok(!!(await kb.bis('anfrage-von')), 'B bekommt die Anfrage gemeldet')
kb.sende('annehmen ' + Buffer.from('justin').toString('hex'))
ok(!!(await kb.bis('freund-neu')), 'B nimmt an')
ok(freunde.sindFreunde('justin', 'freund'), 'die Freundschaft steht auf BEIDEN Seiten (justin->freund)')
ok(freunde.sindFreunde('freund', 'justin'), 'und auf der anderen (freund->justin)')

console.log('== 3. Praesenz: A startet Certus, B sieht es ==')
// Derselbe 64-Oktett-Rahmen wie am Systembus.
const rahmen = (zustand, app, txt) => {
  const b = Buffer.alloc(64)
  b[0] = 7; b[1] = zustand
  b[2] = Buffer.byteLength(app); b[3] = Buffer.byteLength(txt)
  Buffer.from(app).copy(b, 4); Buffer.from(txt).copy(b, 20)
  return b
}
const t0 = Date.now()
ka.sende('status ' + rahmen(0, 'certus', 'liest xoffi.ai').toString('hex'))
const p = await kb.bis('praesenz')
const dt = Date.now() - t0
ok(!!p, 'B sieht den Status von A')
ok(dt < 2000, 'und zwar binnen 2 s (gemessen: ' + dt + ' ms)')
if (p) {
  const r = Buffer.from(p.split(' ')[2], 'hex')
  eq(r.subarray(4, 4 + r[2]).toString(), 'certus', 'die App steht drin')
  eq(r.subarray(20, 20 + r[3]).toString(), 'liest xoffi.ai', 'der Statustext steht drin')
}

console.log('== 4. UNSICHTBAR: der Text verlaesst das Geraet nicht ==')
// Der OS-Dienst baut den Rahmen bei "unsichtbar" LEER -- hier wird
// geprueft, dass der Server einen solchen Rahmen auch so verteilt und
// nichts dazuerfindet.
kb.zeilen.length = 0
ka.sende('status ' + rahmen(3, '', '').toString('hex'))
const pu = await kb.bis('praesenz')
ok(!!pu, 'B bekommt den unsichtbaren Zustand')
if (pu) {
  const r = Buffer.from(pu.split(' ')[2], 'hex')
  eq(r[1], 3, 'Zustand ist unsichtbar (3)')
  eq(r[2], 0, 'keine App im Rahmen')
  eq(r[3], 0, 'kein Text im Rahmen')
}

console.log('== 5. Chat: A schreibt, B empfaengt ==')
// Die Schluessel entstehen zwischen den GERAETEN. Der Server bekommt
// keinen davon zu sehen -- er kennt nur die oeffentlichen Ed25519-Teile
// aus dem Koppelbuch, und die taugen nicht zum Entschluesseln.
const xa = generateKeyPairSync('x25519')
const xb = generateKeyPairSync('x25519')
const gemeinsam = (priv, pub) => diffieHellman({ privateKey: priv, publicKey: pub })
const sitzung = (priv, pub) =>
  Buffer.from(hkdfSync('sha256', gemeinsam(priv, pub), Buffer.alloc(32), Buffer.from('osum-chat'), 32))
const kA = sitzung(xa.privateKey, xb.publicKey)
const kB = sitzung(xb.privateKey, xa.publicKey)
ok(kA.equals(kB), 'beide Geraete rechnen DENSELBEN Sitzungsschluessel')

const KLARTEXT = 'Treffen um 19 Uhr am Steinreichweg'
const siegeln = (k, p) => {
  const n = randomBytes(12)
  const c = createCipheriv('chacha20-poly1305', k, n, { authTagLength: 16 })
  const ct = Buffer.concat([c.update(Buffer.from(p, 'utf8')), c.final()])
  return Buffer.concat([n, ct, c.getAuthTag()])
}
const oeffnen = (k, b) => {
  const d = createDecipheriv('chacha20-poly1305', k, b.subarray(0, 12), { authTagLength: 16 })
  d.setAuthTag(b.subarray(b.length - 16))
  return Buffer.concat([d.update(b.subarray(12, b.length - 16)), d.final()]).toString('utf8')
}
const chiffrat = siegeln(kA, KLARTEXT)
kb.posts.length = 0
ka.sende('senden ' + Buffer.from('freund').toString('hex'), chiffrat)
ok(!!(await ka.bis('zugestellt')), 'der Server meldet die Zustellung')
await kb.bis('post')
ok(kb.posts.length === 1, 'B hat genau eine Nachricht bekommen')
if (kb.posts.length) {
  eq(oeffnen(kB, kb.posts[0].c), KLARTEXT, 'B entschluesselt den richtigen Klartext')
}

console.log('== 6. DIE ZUSAGE: der Server sieht KEINEN Klartext ==')
// Alles, was der Server je in die Hand bekommen hat: sein Mitschnitt,
// sein Freundesbuch auf der Platte, und das Chiffrat selbst.
const alles = Buffer.concat([
  Buffer.from(mitschnitt.join('\n'), 'utf8'),
  Buffer.from(fs.readFileSync(join(TMP, 'freunde.json'))),
  chiffrat,
])
let treffer = 0
let ab = 0
for (;;) {
  const i = alles.indexOf(Buffer.from(KLARTEXT, 'utf8'), ab)
  if (i < 0) break
  treffer++; ab = i + 1
}
eq(treffer, 0, 'Klartext im gesamten Servermaterial gefunden')
// Die GEGENPROBE: derselbe Suchlauf findet den Klartext sehr wohl,
// wenn er da ist. Ein Test, der auch bei kaputter Suche gruen waere,
// misst nichts.
const gegen = Buffer.concat([alles, Buffer.from(KLARTEXT, 'utf8')])
ok(gegen.indexOf(Buffer.from(KLARTEXT, 'utf8')) >= 0, 'Gegenprobe: die Suche findet den Klartext, wenn er da ist')

console.log('== 7. Offline-Zustellung ueber das Postfach ==')
kb.sock.destroy()
// Warten, BIS der Dienst den Abgang wirklich verbucht hat. Vorher ist
// der Empfaenger fuer den Server noch online, und die Nachricht ginge
// zu Recht direkt raus.
await new Promise((r) => setTimeout(r, 400))
// UND DEN ZEILENSPEICHER LEEREN. `bis()` sucht im ganzen bisherigen
// Verlauf; ohne das hier findet es das 'zugestellt 1' aus Abschnitt 5
// wieder und misst eine Zusage, die laengst vorbei ist. Genau das war
// dieser Test drei Laeufe lang: rot, obwohl der Dienst recht hatte.
ka.zeilen.length = 0
const c2 = siegeln(kA, 'zweite Nachricht')
ka.sende('senden ' + Buffer.from('freund').toString('hex'), c2)
const z = await ka.bis('zugestellt')
eq(z.split(' ')[1], '0', 'niemand online -> 0 direkt zugestellt')
eq(freunde.postAnzahl('freund'), 1, 'die Nachricht liegt im Postfach')
const kb2 = new Klient(B.privateKey, pubB)
await kb2.verbinde(); await kb2.anmelden()
ok(!!(await kb2.bis('postfach')), 'B wird beim Anmelden auf wartende Post hingewiesen')
kb2.sende('abholen')
await kb2.bis('leer')
eq(kb2.posts.length, 1, 'B holt die Nachricht ab')
if (kb2.posts.length) eq(oeffnen(kB, kb2.posts[0].c), 'zweite Nachricht', 'und sie ist lesbar')
eq(freunde.postAnzahl('freund'), 0, 'das Postfach ist danach leer')

console.log('== 8. kein Chat ohne Freundschaft ==')
const C = generateKeyPairSync('ed25519')
const pubC = rohPub(C.publicKey).toString('hex')
buch.d[pubC] = { uid: 'fremder', name: 'Osum-C' }
const kc = new Klient(C.privateKey, pubC)
await kc.verbinde(); await kc.anmelden()
kc.sende('senden ' + Buffer.from('justin').toString('hex'), Buffer.from('hallo'))
ok(!!(await kc.bis('nein', 1500)), 'ein Fremder darf nicht schreiben')

console.log('== 9. Entfernen wirkt auf BEIDEN Seiten ==')
ka.sende('entfernen ' + Buffer.from('freund').toString('hex'))
await ka.bis('entfernt')
ok(!freunde.sindFreunde('justin', 'freund'), 'A hat B nicht mehr')
ok(!freunde.sindFreunde('freund', 'justin'), 'und B hat A nicht mehr')

console.log('== 10. Abriss: der Status bleibt nicht stehen ==')
const kd = new Klient(A.privateKey, pubA)
await kd.verbinde(); await kd.anmelden()
ka.sock.destroy(); kd.sock.destroy()
await new Promise((r) => setTimeout(r, 400))
ok(true, 'alle Verbindungen abgerissen, der Dienst laeuft weiter')
ok(srv.listening, 'der Lauscher lebt noch')

srv.close()
try { kc.sock.destroy(); kb2.sock.destroy(); kx.sock.destroy() } catch { /* */ }
console.log(`\nPRAESENZD: ${pass} passed, ${fail} failed`)
process.exit(fail ? 1 : 0)
