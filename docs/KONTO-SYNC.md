# Die Übergabe von KONTO an SYNC

Runde KONTO baut die Identität: anmelden, Token halten, Sitzung
erneuern, abmelden. Sie baut **keinen Abgleich** und **keine
Verschlüsselung von Daten** — das ist Runde SYNC. Damit beide getrennt
bleiben, gibt es genau eine schmale Übergabe, und sie steht hier.

Sie beantwortet drei Fragen und keine vierte:

1. **Wer bin ich?** — Anbieter, Bereich (Mandant), Subjekt.
2. **Wohin gehören meine Daten?** — Datenort und der lokale Benutzer,
   dem das Konto zugeordnet ist.
3. **Womit darf ich reden?** — das Zugriffstoken und sein Ablauf.

## Der Aufruf

```
konto uebergabe --kennung=<kennung>
```

`<kennung>` ist die stabile Kontokennung, die `konto liste` in der
vierten Spalte führt: SHA-256 über **Anbieter + Bereich + Subjekt**,
die ersten acht Oktette in Hexadezimalschreibweise.

Die Ausgabe sind Zeilen der Form `konto: <name> = <wert>`:

```
konto: anbieter = xoffi
konto: bereich  = alpha
konto: subjekt  = 1003
konto: datenort = https://react.xoffi.com
konto: lokal    = justin
konto: zugriff  = <das Zugriffstoken>
konto: ablauf   = 1788686751
```

Rückgabewert `0`, wenn eine gültige Sitzung vorlag; `7`
(`RC_ABGELAUFEN`) und **kein** `zugriff`, wenn keine da ist. SYNC muss
diesen Fall können: das Gerät ist dann weiterhin benutzbar, nur nicht
abgleichbar.

## Die Regeln, die SYNC einhalten muss

* **Der Datenort trennt.** Ein Konto bei Anbieter A und eines bei
  Anbieter B haben getrennte Datenbestände; dasselbe gilt für zwei
  Mandanten desselben Anbieters (`bereich`). Das Verzeichnis, in dem
  SYNC arbeitet, wird deshalb aus der **Kennung** abgeleitet, nie aus
  der E-Mail-Adresse oder dem Anzeigenamen — dieselbe Adresse kann in
  zwei Organisationen existieren, und ein gemeinsames Verzeichnis wäre
  ein Leck über Mandanten hinweg.
* **Ein Format, eine Verschlüsselung, drei Transporte.** SYNC definiert
  das Format der Daten und ihre Verschlüsselung **einmal**. Je Anbieter
  gibt es nur einen dünnen Transport. Zwingt ein Anbieter ein zweites
  Format auf, ist das zu melden und nicht hinzunehmen.
* **Das Token ist flüchtig.** SYNC hält es im Speicher, schreibt es
  nirgendwohin und holt es bei Bedarf neu über diesen Aufruf. Auf der
  Platte liegt es nur gesiegelt, und dafür ist KONTO zuständig
  (`ksiegel.fi`).
* **Kein Recht kommt aus einem fremden Token.** Was im Token eines
  Anbieters an Rollen steht (`is_admin`, `nexus_core_access`,
  `master_session`), ist die Verwaltung einer fremden Firma. SYNC leitet
  daraus **keine** lokale Berechtigung ab. Der Eigentümer der Dateien
  ist und bleibt der lokale Benutzer aus `lokal`.
* **Kein Konto ist ein gültiger Zustand.** Gibt es keine Kontozeile,
  arbeitet das Gerät ohne Abgleich weiter. Kein Dialog, keine Sperre,
  keine Funktion, die verschwindet.

## Was KONTO nicht liefert

Kein Erneuerungstoken, kein Kennwort, keine Kopfzeilen, keine
Verbindungen. Braucht SYNC ein frisches Zugriffstoken, ruft es
`konto status --kennung=<k>` (das erneuert bei Bedarf) und danach
wieder `konto uebergabe`. Der Weg zum Anbieter gehört dem Rücken in
`kernel/app/anb_*.fi`, und er bleibt dort.
