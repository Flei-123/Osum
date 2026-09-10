// tools/bridge/werkzeuge.mjs -- RUNDE BRIDGE-2: DIE WERKZEUGE, GEGEN OSUM.
//
// Aufgerufen von tools/bridge/echtserver.sh, waehrend Osum in QEMU am
// echten JARVIS-Server haengt. Gemessen wird hier NICHT der Adapter --
// das tut test/osumbridge.test.mjs --, sondern DASS DIE WERKZEUGE, DIE
// JARVIS BENUTZT, AN EINEM OSUM-GERAET FUNKTIONIEREN.
//
// Deshalb geht `screenshot` ueber `/api/remote/action`: das ist genau
// der Weg, den `computer(action:"screenshot")` im Server nimmt
// (server.js ruft dort `dev.request('computer_request', ...)`, und
// lib/tools.js ruft dieselbe Methode). Die Datei-Werkzeuge gehen ueber
// `fs_request` -- dieselbe Methode, die `fsReq` in lib/tools.js ruft.
//
// Ausgabe: Zeilen, die mit OK oder FAIL beginnen; alles andere ist eine
// Anmerkung. Das Schalenskript draussen zaehlt sie.
import fs from 'node:fs'

const HTTP = process.env.HTTPPORT
const KEKS = process.env.KEKS
const W = process.env.W
const BASIS = `http://127.0.0.1:${HTTP}`

const sag = (s) => console.log(s)
const ok = (s) => sag('OK ' + s)
const bad = (s) => sag('FAIL ' + s)

async function api(pfad, methode = 'GET', koerper = null) {
  const r = await fetch(BASIS + pfad, {
    method: methode,
    headers: { 'content-type': 'application/json', cookie: KEKS },
    body: koerper ? JSON.stringify(koerper) : undefined,
  })
  const t = await r.text()
  try { return { status: r.status, j: JSON.parse(t) } } catch { return { status: r.status, t } }
}

// ---------------------------------------------------------- 1. list_devices
{
  const r = await api('/api/remote/devices')
  const namen = r.j?.devices || []
  if (namen.includes('Osum-QEMU')) ok(`list_devices nennt das Osum-Geraet: ${namen.join(', ')}`)
  else bad(`list_devices kennt es nicht (${JSON.stringify(namen)})`)
}

// Die Datei-Werkzeuge brauchen den Weg, den lib/tools.js nimmt. Der
// Server hat dafuer keinen HTTP-Endpunkt (er ist fuer das LLM da), also
// wird hier derselbe Aufruf ueber einen kleinen Pruef-Endpunkt gemacht:
// /api/osum/probe reicht ein fs_request durch und gibt die Antwort.
async function fsReq(op, m) {
  const r = await api('/api/osum/probe', 'POST', { device: 'Osum-QEMU', op, ...m })
  return r.j || {}
}

// ---------------------------------------------------------- 2. remote_shell
{
  const r = await fsReq('run', { command: '/bin/echo hallo-vom-server' })
  if (r.error) bad(`remote_shell: ${r.error}`)
  else if (/hallo-vom-server/.test(r.text || '')) ok('remote_shell fuehrt /bin/echo aus und bringt die Ausgabe zurueck')
  else bad(`remote_shell: unerwartete Ausgabe ${JSON.stringify((r.text || '').slice(0, 80))}`)
}
{
  const r = await fsReq('run', { command: '/bin/ls /' })
  if (r.error) bad(`remote_shell /bin/ls: ${r.error}`)
  else ok(`remote_shell /bin/ls / liefert ${String(r.text || '').split('\n').filter(Boolean).length} Eintraege`)
}
// Die Gegenprobe: ein Befehl, der NICHT in der Rechteliste steht.
{
  const r = await fsReq('run', { command: '/bin/chmod 777 /' })
  if (r.error && /rechte|erlaubt|nicht/i.test(r.error)) ok('ein NICHT erlaubter Befehl wird abgelehnt -- die Rechteliste gilt auch am echten Server')
  else bad(`ein nicht erlaubter Befehl kam durch: ${JSON.stringify(r)}`)
}

// ---------------------------------------------------------- 3. remote_read
{
  const r = await fsReq('read', { path: '/var/jarvis/gruss.txt' })
  if (r.error) bad(`remote_read: ${r.error}`)
  else if (/hallo aus osum/.test(r.text || '')) ok('remote_read liest /var/jarvis/gruss.txt')
  else bad(`remote_read: unerwarteter Inhalt ${JSON.stringify((r.text || '').slice(0, 60))}`)
}
{
  const r = await fsReq('read', { path: '/etc/jarvis/geraet.key' })
  if (r.error) ok('remote_read auf den privaten Schluessel wird abgelehnt')
  else bad('der private Schluessel liess sich lesen -- das darf nicht sein')
}

// ------------------------------------------- 4. remote_write + zuruecklesen
const MARKE = 'BRIDGE2-' + Date.now()
{
  const r = await fsReq('write', { path: '/var/jarvis/vomserver.txt', content: MARKE + '\n' })
  if (r.error) bad(`remote_write: ${r.error}`)
  else ok('remote_write schreibt /var/jarvis/vomserver.txt')
}
{
  const r = await fsReq('read', { path: '/var/jarvis/vomserver.txt' })
  if (r.error) bad(`das Zuruecklesen scheiterte: ${r.error}`)
  else if (String(r.text || '').includes(MARKE)) ok('und das Zuruecklesen zeigt GENAU das, was geschrieben wurde')
  else bad(`zurueckgelesen kam etwas anderes: ${JSON.stringify((r.text || '').slice(0, 60))}`)
}

// ---------------------------------------------------- 5. computer(screenshot)
{
  const r = await api('/api/remote/action', 'POST', { device: 'Osum-QEMU', action: 'screenshot' })
  if (r.j?.ok && r.j?.image) {
    const png = Buffer.from(r.j.image, 'base64')
    fs.writeFileSync(`${W}/schirm.png`, png)
    if (png.subarray(0, 8).toString('hex') === '89504e470d0a1a0a') {
      ok(`computer(screenshot) bringt ein PNG: ${png.length} Oktette`)
      // Die Masse aus dem IHDR -- ein PNG mit 0x0 waere auch ein PNG.
      const w = png.readUInt32BE(16)
      const h = png.readUInt32BE(20)
      if (w > 100 && h > 100) ok(`und es ist ${w}x${h} gross -- ein echter Schirm`)
      else bad(`das PNG ist ${w}x${h} -- das ist kein Bildschirm`)
    } else bad('die Antwort ist kein PNG')
  } else {
    bad(`computer(screenshot): ${r.j?.error || JSON.stringify(r.j).slice(0, 120)}`)
  }
}
