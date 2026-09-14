# Runde FREMDFS — fremde Dateisysteme lesen (ext4 und NTFS)

Zweig `fremdfs`, abgezweigt von `main` (`ce4a232`).
Gemessen mit `bash tools/fremdfs/run.sh` (**131 Zusagen, 0 gescheitert**) und
`bash tools/fremdfs/tempo.sh`.

Diese Runde schließt die Lücke, die `docs/RUNDE-DUALBOOT.md` offen
gelassen hat. Dort steht, dass OrientOS sich neben Windows auf dieselbe
Platte installieren lässt. Danach stand der Benutzer vor einer Platte,
auf der **seine** Dateien lagen — und kam nicht heran. Ein Zweitsystem,
das die Daten des Erstsystems nicht sieht, ist ein besserer
Bildschirmschoner.

---

## 1. Die Antwort

**Ja, beide — lesend, und die Prüfsummen stimmen.**

OrientOS hängt eine ext4- und eine NTFS-Partition ein, der Explorer und
`ls` zeigen den Inhalt, und jede Datei kommt **Oktett für Oktett**
richtig an. Gemessen wird das nicht durch Hinsehen, sondern so:

> Der **Wirt** legt die Abbilder mit den echten Werkzeugen an
> (`mkfs.ext4` + `debugfs` + `e2fsck`, `mkntfs` + libntfs-3g), baut
> darauf einen bekannten Baum und merkt sich jede SHA-256.
> **Osum** liest die Dateien im laufenden Kernel über gewöhnliche
> `open`/`read`-Aufrufe und rechnet die SHA-256 **selbst**
> (`kernel/user/sha.fi`, gemessen in der Runde TRESOR gegen FIPS 180-4).
> Die zwei Summen werden verglichen.

Was **nicht** geht und mit Absicht nicht geht: **schreiben**. Beide
Treiber tragen `vfsops.OP_READONLY` und nicht mehr; `vfs.can` lässt ein
`write` gar nicht erst zum Treiber durch. Die Begründung steht in
Abschnitt 6.

---

## 2. Was gebaut wurde

| Datei | Zeilen | Was |
|---|---:|---|
| `kernel/ext4.fi` | ~1240 | ext4 lesend: Superblock, Blockgruppen, Inodes, **Extent-Bäume**, Verzeichnisse (auch htree), symbolische Verweise, 64-Bit |
| `kernel/ntfs.fi` | ~1390 | NTFS lesend: Bootsektor, `$MFT`, **Fixups**, residente und nichtresidente Attribute, **Datenläufe**, `$I30`-Indizes, lange Namen |
| `kernel/user/fremdfs.fi` | ~430 | das Messprogramm in Ring 3: liest, hasht, zählt, meldet jede Antwort als Zahl |
| `kernel/user/fftempo.fi` | ~110 | dasselbe ohne Hash — nur die Zeit |
| `tools/fremdfs/bild.sh` | ~330 | die Prüfbilder, vom Wirt gebaut, samt Gegenproben |
| `tools/fremdfs/ntfsbaum.c` | ~260 | einen Baum in ein NTFS legen **ohne** es einzuhängen (libntfs-3g ohne FUSE) |
| `tools/fremdfs/ext4info.py` | ~180 | ein ext4 mit fremden Augen lesen: Baumtiefe, Extent-Zahl, htree-Bit |
| `tools/fremdfs/run.sh` | ~550 | die Abnahme: 110 Zusagen |
| `tools/fremdfs/tempo.sh` | ~130 | die Zeitmessung gegen OFS |
| `tools/fremdfs/einzeln.sh` | ~85 | ein einzelner Lauf zum Nachsehen |
| `kernel/ext4-aus.fi` | ~115 | die Leerfassung für `--ohne-ext4` |
| `kernel/ntfs-aus.fi` | ~110 | die Leerfassung für `--ohne-ntfs` |
| `tools/fremdfs/bild-explorer.sh` | ~120 | die Bilder vom Dateimanager |

Angebunden wie FAT32: `kernel/vfsops.fi` (`FS_EXT4`, `FS_NTFS`),
`kernel/vfs.fi` (`ops_of`, `mount_at`, `umount_index`), `kernel/sys.fi`
(`fstype_of` kennt `ext4`, `ext2`, `ext3`, `ntfs`).
`kstate.EXT4_OFF = 0xF3000`, `kstate.NTFS_OFF = 0xF6000`, je drei Seiten;
`tools/kernel/memmap.py` rechnet beide samt ihrer Untergliederung nach.

---

## 3. Die Messung

```
FREMDFS: 131 bestanden, 0 gescheitert
```

Was darin steckt:

| Abschnitt | Zusagen | Was |
|---|---:|---|
| 1 | 9 | die Speicherkarte, die Seitenaufteilung, `OP_READONLY`, Gegenprobe |
| 2 | 2 | der Kern und 13 Programme aus **beiden** Übersetzern (firnc0, firnc1) |
| 3 | 6 | die Prüfbilder — und dass sie wirklich prüfen, was sie sollen |
| 4 | 1 | die Wurzelplatte |
| 5 | 26 | **ext4**, 1024er Blöcke |
| 5b | 26 | **ext4**, 4096er Blöcke — dieselbe Arbeit, andere Geometrie |
| 6 | 24 | **NTFS** |
| 7 | 13 | die Gegenproben |
| 7b | 21 | **die Abschaltbarkeit** (Abschnitt 8) |
| 8 | 2 | die Zeit |

### 3.1 Der Prüfbaum

Jeder Eintrag prüft etwas Bestimmtes, und keiner ist Zierde:

| Eintrag | wofür |
|---|---|
| `hallo.txt` | die einfachste Datei |
| `leer.bin` | **null Oktette** — bei NTFS ein `$DATA` ohne Inhalt, bei ext4 ein Extent-Baum ohne Extents |
| `mittel.bin` | 200 KiB — mehrere Blöcke |
| `gross.bin` | 6 MiB, **absichtlich zerstückelt**: Extent-Baum mit **Tiefe 1** und **103 Blatt-Extents** (gemessen, nicht gehofft) |
| `a/b/c/d/tief.txt` | vier Ebenen |
| `umlaut-äöü.txt` | Umlaute **im Namen** |
| `verweis.txt` | symbolischer Verweis, Ziel **inline im Inode** (9 Oktette) |
| `langverweis.txt` | symbolischer Verweis, Ziel **in einem Datenblock** (98 Oktette) |
| `viele/datei-000..511` | 512 Einträge — erzwingt bei ext4 einen **htree**-Index (`EXT4_INDEX_FL` gemessen) und bei NTFS einen `$I30`-Baum mit `$INDEX_ALLOCATION` |

Dass der Extent-Baum wirklich einer ist, macht `e2fsck -fyD` und die
Zerstückelung: erst 200 Brocken anlegen, jeden zweiten löschen, dann die
große Datei schreiben. `ext4info.py` liest danach `eh_depth` aus dem
Inode. Ohne diese Zahl wäre „der Treiber kann Extent-Bäume" eine
Hoffnung — bei Tiefe 0 stehen alle Extents im Inode und der Baum wird
nie betreten.

### 3.2 Die Gegenproben

Ohne sie ist ein Prüfstand eine Vorführung:

| Fall | Erwartung | gemessen |
|---|---|---|
| ext4 mit zerstörter Magie | abgelehnt, nicht hängen | `mount = 0`, `ext4: nicht ext4 (1` |
| FAT32 als ext4 eingehängt | abgelehnt | `mount = 0` |
| ext4 als vfat eingehängt | abgelehnt | `mount = 0` |
| **abgeschnittenes** ext4 | abgelehnt | `mount = 0`, `ext4: nicht ext4 (6` |
| NTFS mit zerstörter Kennung | abgelehnt | `mount = 0` |
| **unsauber** ausgehängtes ext4 | erkannt + Warnung | `mount = 1`, `ext4: WARNUNG unsauber ausgehaengt` |
| Schreibversuch | scheitert | `schreib = 0` |
| Speicherkarte mit Kollision | Prüfer schlägt an | schlägt an |

Der Beendigungscode von QEMU ist bei jedem dieser Fälle **21** („der
Kernel hat sich selbst beendet") und nicht das Zeitlimit — ein kaputtes
Dateisystem darf den Kern nicht anhalten, und das ist hier gemessen und
nicht angenommen.

### 3.3 Die Lesegeschwindigkeit

`bash tools/fremdfs/tempo.sh`, 2000000 Oktette am Stück, Puffer 4096,
je drei Läufe, der schnellste zählt, `-accel kvm -cpu host`:

| System | ms | MB/s |
|---|---:|---:|
| **OFS** (eigenes) | 810 | **2,4** |
| **NTFS** | 1959 | **1,0** |
| **ext4** | 2327 | **0,8** |

**Warum 2000000 und nicht die 6 MiB des Prüfbaums:** eine Datei auf OFS
kann in dieser Fassung höchstens 2134016 Oktette groß sein
(`docs/OFS-LIMITS.md`). Ohne einen Wert für OFS gäbe es keinen
Vergleich, und nur eine Zahl, die auf **alle drei** passt, sagt etwas
über die Treiber statt über die Grenzen des einen.

**Die fremden sind langsamer, und das ist ehrlich so.** Der Grund ist
kein Formatnachteil, sondern eine Schleife: `f_read` lädt für **jeden**
Block den Inode neu (`inode_load` bei ext4, `mft_lesen` bei NTFS), und
bei ext4 kam bis zu dieser Runde noch ein Abstieg in den Extent-Baum je
Block dazu. Der Extent-Zwischenspeicher hat davon 2703 auf 2327 ms
gebracht; der Rest steckt im Neuladen des Inodes und ist in
Abschnitt 7 als offener Punkt vermerkt. OFS hat diesen Aufwand nicht,
weil `sys.fi` dort den geraden Weg von Runde 62 nimmt.

---

## 4. Was unterstützt wird — und was ausdrücklich nicht

### ext4 (`kernel/ext4.fi`)

**Kann:** Superblock und Blockgruppen (auch mit 64-Bit-Merkmal,
`s_desc_size` 64); Inodes 128 und 256 Oktette; **Extent-Bäume** beliebiger
Tiefe bis 5, einschließlich Index-Knoten; **große Dateien** (`i_size_high`
wird gelesen); **Löcher** (als Nullen, und nicht initialisierte Extents
`ee_len > 32768` ebenfalls als Nullen — sonst käme alter Platteninhalt
heraus); Verzeichnisse linear **und htree-indiziert**; **symbolische
Verweise** inline und in Datenblöcken; Blockgrößen 1024, 2048 und 4096;
Rechte aus `i_mode`.

**Kann nicht, und lehnt deshalb ab:** `inline_data`, `encrypt`,
`casefold`, `compression` — jedes davon verschiebt, **wo** die Daten
liegen; ein Dateisystem damit zu lesen, als wäre es gewöhnlich, liefert
Müll statt eines Fehlers. Blockgrößen über 4096.

**Kann nicht, und sagt es:** **schreiben** (gar nicht).
**Prüfsummen** (`metadata_csum`) werden **nicht** geprüft — ein Leser,
der sie falsch prüft, lehnt gesunde Platten ab; das ist eine eigene
Runde wert.

**Unter Vorbehalt:** der Weg über **indirekte Blöcke** (ext2/ext3 ohne
Extents) ist eingebaut (`block_of_indirect`), aber in dieser Runde
**nicht gemessen** — alle Prüfbilder sind mit Extents gebaut. Wer sich
darauf verlässt, misst ihn bitte erst.

### NTFS (`kernel/ntfs.fi`)

**Kann:** Bootsektor (auch mit negativ kodierter Verbandgröße);
`$MFT` mit **Fixups** (die Stelle, an der jeder erste NTFS-Leser falsch
liegt — das letzte Wort jedes Sektors ist auf der Platte durch eine
Prüfzahl ersetzt); **residente** Attribute (kleine Dateien stehen im
MFT-Eintrag selbst) und **nichtresidente**; **Datenläufe** mit
vorzeichenbehafteten, relativen Versätzen und dünn besetzten Läufen;
`$INDEX_ROOT` **und** `$INDEX_ALLOCATION` (INDX-Blöcke, ebenfalls mit
Fixups); **lange Namen** in UTF-16, nach UTF-8 gewandelt; der DOS-Name
(Namensraum 2) wird übergangen, sonst erschiene jede Datei zweimal;
die **Systemdateien** (MFT 0..15: `$MFT`, `$Boot`, `$Bitmap`, …) werden
verborgen, so wie Windows und ntfs-3g es tun.

**Erkennt und lehnt ehrlich ab:** **komprimierte** Attribute (LZNT1) und
**verschlüsselte** (EFS). `f_read` gibt dafür nichts zurück statt
Pack-Blöcke auszuliefern und sie Dateiinhalt zu nennen.

**Kann nicht:** schreiben; Reparse-Punkte auflösen (die NTFS-Fassung
eines symbolischen Verweises — sie erscheinen als gewöhnliche
Einträge); alternative Datenströme (gelesen wird der unbenannte
`$DATA`); Zeichen jenseits der Grundebene im Namen (werden zu `_`).

**Eine bekannte Grenze:** die `$MFT` wird als **zusammenhängend** ab
`S_MFTLCN` gelesen. Für die ersten Einträge — und um die geht es —
stimmt das, und so findet auch der Startvorgang von Windows seinen Weg
hinein. Eine Platte mit stark zerstückelter `$MFT` braucht deren eigene
Datenlauftafel; das steht in Abschnitt 7.

---

## 5. Das unsauber ausgehängte Dateisystem

Der Auftrag ließ die Wahl zwischen „ablehnen" und „nur lesend mit
Warnung" und verlangte eine Begründung.

**Entscheidung: einhängen, nur lesend, mit Warnung im Klartext.**

Warum nicht ablehnen: dieser Treiber kann ohnehin **nur** lesen. Der
Schaden, vor dem eine Ablehnung schützt, ist das **Schreiben** auf ein
Dateisystem, dessen Journal noch offene Einträge hat — das kann hier gar
nicht passieren. Ablehnen würde also niemanden schützen, aber genau dann
die Daten verweigern, wenn man sie am dringendsten braucht: **nach einem
Absturz**, wenn man von der anderen Seite an seine Dateien will. Das ist
der ganze Zweck dieser Runde.

Was der Benutzer wissen **muss**, und was die Warnung sagt: was hier zu
lesen ist, ist der Stand **vor** dem Journal. Ein Linux, das gleich
danach startet, spielt es ein und sieht möglicherweise **neuere** Daten.
Wer hier eine Datei kopiert, kopiert unter Umständen eine ältere
Fassung.

Erkannt wird beides: `s_state` Bit 0 (`EXT2_VALID_FS`) und das Merkmal
`NEEDS_RECOVERY` (`s_feature_incompat` Bit 2). Gemessen an einem Abbild,
dem beide Zahlen von Hand gesetzt wurden — also genau das, was ein
abgestürztes Linux hinterlässt.

---

## 6. Warum nur lesend

ext4 schreibend hieße: Journal führen, Blockgruppen-Zähler nachführen,
und `metadata_csum` über Superblock, Gruppenbeschreiber, Inodes,
Verzeichnisblöcke **und** Extent-Knoten neu rechnen. NTFS schreibend
hieße: `$MFT` fortschreiben, `$Bitmap` führen, `$LogFile` füllen, die
`$I30`-Bäume ausgleichen.

Jede einzelne dieser Stellen falsch gemacht heißt: **die Platte ist für
das andere System kaputt** — und zwar meistens erst beim nächsten
`e2fsck` bzw. `chkdsk` sichtbar. Der Auftrag dieser Runde ist das Lesen;
das Schreiben ist keine halbe Runde mehr, sondern eine eigene. Bis dahin
sagt dieser Treiber **nein**, statt es halb zu können.

---

## 7. Drei Fehler, die nur eine Messung findet

Sie stehen hier, weil sie alle drei **nicht** im Quelltext zu sehen
waren und alle drei dieselbe Lehre tragen.

**1. Die Partitionsweiche in `sys.fi`.** Dort stand
`if ft == FS_FAT || ft == FS_OFS` — und die zwei neuen Treiber fielen
stillschweigend durch: sie bekamen Gerät 0 und ersten Sektor 0, also die
RAM-Platte statt der Partition. Von außen sah das aus wie „der Treiber
erkennt sein eigenes Dateisystem nicht"; der Fehler lag eine Schicht
darüber. **Jedes Dateisystem auf einem Blockgerät braucht diese
Auflösung** — nur `/proc` und `/dev` nicht.

**2. Die Knotentafel lag im Puffer.** Sie fing bei `+0x400` an und war
`24 * 48 = 0x480` Oktette lang, endete also bei `+0x880` — und der erste
große Puffer stand bei `+0x800`. Die letzten drei Knoten lagen damit
**unter** dem Puffer, in den jeder MFT-Eintrag gelesen wird. Wer eine
Datei öffnete, die einen davon bekam, verlor ihre Felder beim ersten
Lesen; `N_DIR` wurde 1, `f_read` hielt die Datei für ein Verzeichnis und
gab 0 zurück. **Sichtbar wurde das als Prüfsumme der ersten 4096
Oktette** — und gesucht wurde zuerst im Datenlauf. Die Tafel hat jetzt
16 Plätze zu 56 Oktetten (Ende `0x780`), `run.sh` rechnet die
Aufteilung nach, und `memmap.py` kennt die Unterbereiche.

**3. Latin-1 statt UTF-8.** `name_wandeln` legte jedes UTF-16-Zeichen
unter `0x100` als **ein** Oktett ab. Für ASCII stimmt das; `ä` (U+00E4)
ergibt so `0xE4`, während derselbe Name aus der Shell als `0xC3 0xA4`
kommt — OrientOS rechnet in UTF-8. Die beiden waren nie gleich, und
`umlaut-äöü.txt` war auf NTFS nicht zu öffnen, obwohl `ls` ihn anzeigte.

Dazu kam eine Lücke **in der Schicht darüber**: `do_readlink` ging
geradewegs an `fs.path_nofollow`, also an OFS, und kannte die
K14-Weiche nicht. Ein Verweis auf einer eingehängten Platte war über
`stat` als Verweis zu sehen, aber sein Ziel nicht zu lesen. Jetzt fragt
auch `readlink` zuerst die Einhängetafel.

---

## 8. Abschaltbar, einzeln — und was jedes kostet

Justins Zusatzvorgabe vom 14.09.2026: die zwei Dateisysteme sollen sich
**einzeln** aus dem Abbild nehmen lassen, das System muss ohne sie
unverändert laufen, ein Einhängeversuch muss einen klaren Fehler geben
statt zu hängen — und der Standardzustand ist zu **begründen**, mit
Zahlen statt Gefühl.

### 8.1 Wie

Kein Schalter zur Laufzeit, kein `#ifdef`, kein ladbares Modul,
sondern der Griff, den dieser Baum für so etwas schon hat: eine
**Leerfassung** tritt an die Stelle des Treibers, und danach steht im
Baum, aus dem der Übersetzer liest, keine Zeile des Dateisystems mehr.
Genau so arbeiten `wg-aus.fi` (Tunnel), `gfx-aus.fi` (die GUI-lose
Fassung) und `ps2m-aus.fi` (Zeigegerät).

```sh
./tools/build-kernel.sh abbild.mb --ohne-ext4      # nur NTFS
./tools/build-kernel.sh abbild.mb --ohne-ntfs      # nur ext4
./tools/build-kernel.sh abbild.mb --ohne-fremdfs   # keins von beiden
```

Auch über die Umgebung (`OSUM_EXT4=off`, `OSUM_NTFS=off`). Die
Schlusszeile des Baus sagt, was drin ist:

```
abbild.mb (5253636 Oktette, Stufe 0, gui=on, …, ext4=an, ntfs=an)
```

**Warum kein ladbares Modul.** Dieser Kernel hat einen Modullader
(`kernel/module.fi`), aber ein Dateisystemtreiber ist der falsche
erste Kunde dafür: er wird **beim Einhängen** gebraucht, und das kann
der Fall sein, bevor eine Platte da ist, von der man nachladen könnte —
beim Installieren aus dem Netz oder bei einer Wurzel, die selbst auf dem
fremden Dateisystem liegt. Eine Bauoption hat diese Reihenfolgefrage
nicht. Sie nimmt den Treiber **vollständig** heraus, statt ihn zur
Laufzeit schlafen zu legen, und das ist genau das, was die Vorgabe
verlangt („aus dem Abbild nehmen").

`kernel/ext4-aus.fi` und `kernel/ntfs-aus.fi` exportieren **dieselben**
Namen und dieselbe `ops`-Tafel mit leeren Rümpfen; `mask` ist **0**, und
`mount_probe` gibt **0** zurück. `vfs.mount_at` nimmt die Einhängung
daraufhin zurück, und `mount` antwortet **-ENODEV** — „Dateisystem nicht
unterstützt", sofort, ohne einen einzigen Lesezugriff auf die Platte.

### 8.2 Was es kostet — gemessen

Vier Abbilder, derselbe Übersetzer, dieselben Optionen:

| Abbild | Oktette | Unterschied |
|---|---:|---:|
| voll (Standard) | 5 253 636 | — |
| `--ohne-ext4` | 5 203 236 | **−50 400** (49,2 KiB) |
| `--ohne-ntfs` | 5 189 928 | **−63 708** (62,2 KiB) |
| `--ohne-fremdfs` | 5 143 620 | **−110 016** (107,4 KiB) |

Ohne die Symboltafel (`--ohne-symbole`), also das reine Programm:

| Abbild | Oktette | Unterschied |
|---|---:|---:|
| voll | 4 504 068 | — |
| `--ohne-fremdfs` | 4 406 340 | **−97 728** (95,4 KiB) |

**Beide zusammen sind 2,1 % des Abbilds.** NTFS kostet mehr als ext4,
obwohl beide etwa gleich lang sind — die Fixup-Rechnung, die
Datenlauf-Entzifferung und die UTF-16-Wandlung erzeugen mehr Code als
die Extent-Suche.

**Was es beim START kostet: nichts Messbares.** Die zwei Treiber haben
keine `init`-Funktion und stehen in keiner Startreihenfolge; sie werden
zum ersten Mal angefasst, wenn jemand `mount` mit ihrer Art aufruft.
Ihre `kdata`-Seiten (je drei) sind Adressen in einem Bereich, der
ohnehin reserviert ist — sie werden nicht angelegt, sondern liegen da.
Was die Abnahme davon prüft: das Abbild ohne beide kommt hoch und
arbeitet auf der eigenen Platte unverändert weiter (Abschnitt 7b).

### 8.3 Der Standard: **an**

Justins Vorgabe war „an, wenn der Platzkostenpunkt vertretbar ist; die
gemessene Größe entscheidet". Die gemessene Größe ist **107,4 KiB von
5,25 MB**, also **2,1 %** — und dafür gibt es die eine Sache, wegen der
diese Runde überhaupt stattfand: wer nach einer Dual-Boot-Installation
seine alten Dateien sucht, findet sie. Ein Zweitsystem, das dafür erst
neu gebaut werden müsste, wäre genau dann nutzlos, wenn man es braucht.

**Also: beide im Standardabbild AN.**

Wo das anders ist, und wo die Schalter deshalb hingehören:

- **Ein Server** (`--gui off`) hat weder Windows noch ein Linux neben
  sich; `--ohne-fremdfs` spart dort 107 KiB, die niemand vermisst.
- **Ein Abbild für einen Rechner mit nur einem System** — dasselbe.
- **Ein eingebettetes Ziel**, auf dem jedes KiB zählt.

Die Abnahme misst beide Richtungen: dass die Schalter wirklich etwas
ausbauen (das Abbild **muss** kleiner werden), dass sie **einzeln**
wirken (ohne ext4 geht NTFS weiter und umgekehrt), dass der
abgeschaltete Treiber sich mit **keiner Zeile** meldet, und dass ein
Einhängeversuch sauber scheitert statt zu hängen (Beendigungscode 21,
nicht das Zeitlimit).

---

## 9. Offene Punkte

- **Schreiben.** Beide nur lesend. Siehe Abschnitt 6.
- **Die Geschwindigkeit.** `f_read` lädt für jeden Block den Inode bzw.
  den MFT-Eintrag neu. Ein Zwischenspeicher dafür (ein Eintrag je
  offenem Knoten) wäre die nächste Verbesserung und dürfte den Abstand
  zu OFS weitgehend schließen; der Extent-Zwischenspeicher hat den
  ersten Teil davon schon gebracht (2703 → 2327 ms).
- **ext2/ext3 ohne Extents.** Der Weg ist da, gemessen ist er nicht.
- **Zerstückelte `$MFT`.** Siehe Abschnitt 4.
- **`metadata_csum` prüfen.** Eigene Runde.
- **LZNT1 entpacken.** Komprimierte NTFS-Dateien werden erkannt und
  abgelehnt; sie zu lesen ist eine eigene Runde.
- **Reparse-Punkte.** NTFS-Verweise werden nicht aufgelöst.
- **Der Explorer** zeigt die fremden Dateisysteme über dieselbe
  VFS-Schicht wie FAT32; eigene Sinnbilder je Dateisystemart gibt es
  nicht.

---

## 10. Das Bild

`docs/bilder/fremdfs-ext4-2-fremd.png` zeigt den Dateimanager mit der
**ext4-Partition** unter `/mnt`: `gross.bin`, `leer.bin`, `mittel.bin`,
`hallo.txt`, `umlaut-äöü.txt` mit den Umlauten an der richtigen Stelle,
die Verzeichnisse `a/` und `viele/`, dazu die beiden Verweise. In der
Seitenleiste steht die fremde Platte als eigener Träger, und der
Kernel hat sie als `ro=1` gemeldet — nur lesend, so wie eingehängt.

Daneben: `-3-viele.png` (das Verzeichnis mit 512 Einträgen, htree) und
`-4-tief.png` (`/mnt/a/b/c/d`, vier Ebenen tief). Erzeugt mit

```sh
bash tools/fremdfs/bild-explorer.sh ext4 /tmp/bild
```

---

## 11. Nachfahren

```sh
git checkout fremdfs
bash tools/fremdfs/run.sh        # alle Zusagen, baut alles selbst
bash tools/fremdfs/tempo.sh      # die Zeit gegen OFS
bash tools/check-ui.sh           # bleibt grün
```

Einen einzelnen Fall nachsehen, mit voller serieller Ausgabe und ohne
dass hinterher aufgeräumt wird:

```sh
bash tools/fremdfs/bild.sh /tmp/bild
bash tools/fremdfs/einzeln.sh ext4 /tmp/bild/ext4.img
bash tools/fremdfs/einzeln.sh ntfs /tmp/bild/ntfs.img 'mount /dev/hdb1 /mnt ntfs -r;ls /mnt'
```

Die Abschaltbarkeit einzeln nachbauen:

```sh
./tools/build-kernel.sh /tmp/voll.mb  --stufe 0
./tools/build-kernel.sh /tmp/ohne.mb  --stufe 0 --ohne-fremdfs
stat -c%s /tmp/voll.mb /tmp/ohne.mb
```

**Ein Hinweis zum Wirt:** `bild.sh` schreibt mit `debugfs` und
libntfs-3g **in die Abbilder** statt sie einzuhängen — in einem
LXC-Behälter gibt es weder `/dev/loop*` noch `/dev/fuse`. Gebraucht
werden `e2fsprogs`, `ntfs-3g`, `ntfs-3g-dev` und `gcc`. Die Abbilder
sind dünn besetzt und belegen zusammen etwa 77 MB.
