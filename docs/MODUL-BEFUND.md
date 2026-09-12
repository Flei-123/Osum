# MODUL-BEFUND — kann Osum Treiber nachladen wie Windows?

Arbeitsbaum `/root/osum-modul`, Zweig `modul`, abgezweigt von `main`
(`163984d`). Recherche und Messungen vom 02.09.2026 auf dem üblichen
Wirt (AMD EPYC 7571, 12 Kerne, 19 GiB, `/dev/kvm` vorhanden).

**Die Frage des Eigners, wörtlich:**

> „Wie macht es Windows? Bei der GPU steht da Basic Display Driver, und
> dann kann ich mir z. B. von NVIDIA GPU-Treiber herunterladen."

Dieses Dokument beantwortet sie in zwei Teilen: **was wirklich der Fall
ist** (Teil 1) und **was daraus für Osum folgt** (Teil 2). Der gebaute
Prototyp steht in `docs/RUNDE-MODUL.md`.

**Die kurze Antwort, damit sie nicht erst am Ende steht:** Ja, Osum kann
Treiber nachladen — der Prototyp dieser Runde tut es. Nein, es wird nie
einen NVIDIA-Treiber für Osum geben, und das liegt nicht an Osum. Beides
wird unten begründet.

---

# TEIL 1 — DER BEFUND

## 1. Wie Windows es macht

### 1.1 Der Microsoft Basic Display Adapter

`BasicDisplay.sys` ist ein generischer Anzeigetreiber, der mit Windows
mitgeliefert wird. Microsofts eigene Beschreibung nennt seinen Zweck:

> „*BasicDisplay*'s primary purpose is to enable Windows to write to the
> display controller's **linear frame buffer**."¹

Er wird geladen, wenn kein Herstellertreiber vorhanden ist, wenn der
vorhandene nicht funktioniert oder abgeschaltet ist, im abgesicherten
Modus, und in den frühen Phasen des Windows-Setups.¹

Wie er an den Rahmenpuffer kommt, hängt von der Firmware ab:

> „*BasicDisplay* supports Unified Extensible Firmware Interface (UEFI)
> Graphics Output Protocol (GOP)."¹
>
> „On UEFI platforms, *BasicDisplay* **inherits the linear frame buffer
> that is set during boot**. In this case, **no mode or resolution
> changes are possible**."¹

Auf Legacy-BIOS-Systemen kann er das Video-BIOS (VBE) benutzen und dann
Modi wechseln — aber nur auf einem Monitor.¹

Drei Dinge, die man daraus mitnehmen soll:

1. **Der Grundzustand ist ein Rahmenpuffer, den die FIRMWARE gesetzt
   hat.** Nicht der Treiber setzt den Modus, sondern UEFI, und der
   Treiber erbt ihn.
2. **Deshalb ist er unveränderlich.** „no mode or resolution changes are
   possible" ist keine Nachlässigkeit, es ist die logische Folge davon,
   dass niemand die Karte wirklich programmiert.
3. **3D fehlt nicht, es ist nur nicht beschleunigt.** BDD läuft immer
   zusammen mit `BasicRender`, das WARP bereitstellt — Direct3D in
   Software auf der CPU.¹ ² Die verbreitete Formulierung „BDD kann kein
   3D" ist also ungenau; richtig ist „keine Hardwarebeschleunigung".

### 1.2 WDDM: zwei Hälften, und beide muss der Hersteller liefern

> „The Windows Display Driver Model (WDDM) has user-mode and kernel-mode
> components."³
>
> „The UMD is a **dynamic-link library (DLL)** that the Direct3D runtime
> loads."³
>
> „The KMD communicates with *Dxgkrnl* and the graphics hardware."³
>
> „**A graphics hardware vendor must supply both a UMD and KMD.**"³

Der Weg eines Zeichenbefehls: Anwendung → Direct3D-Laufzeit → **UMD
(DLL, Ring 3)** → `gdi32`-Thunk → **`dxgkrnl.sys` / `dxgmms2.sys`
(Ring 0)** → **KMD (`.sys`)** → GPU.³

Die Naht dazwischen sind zwei Funktionszeigertafeln, die in **beide**
Richtungen zeigen:

* **`DRIVER_INITIALIZATION_DATA`** — der Treiber gibt dem Betriebssystem
  seine `DxgkDdi*`-Zeiger. Er tut das, indem seine `DriverEntry`-Routine
  `DxgkInitialize` ruft:
  > „A kernel-mode display miniport driver's (KMD) **DriverEntry**
  > routine calls the system-supplied **DxgkInitialize** function to load
  > and initialize the DirectX graphics kernel subsystem
  > (*Dxgkrnl.sys*)."⁴
* **`DXGKRNL_INTERFACE`** — das Betriebssystem gibt dem Treiber seine
  `DxgkCb*`-Zeiger:
  > „The **DXGKRNL_INTERFACE** structure contains a handle to a display
  > adapter and a set of pointers to functions implemented by the
  > **display port driver**, which is a part of *Dxgkrnl*."⁵

Das ist strukturell dasselbe, was `kernel/ksym.fi` und
`kernel/modtab.fi` in dieser Runde für Osum tun: eine Tafel nach unten
(was der Kern anbietet) und eine Tafel nach oben (was der Treiber kann).

### 1.3 Die versionierte Schnittstelle — der eigentliche Grund

Beide Tafeln tragen eine **Fassungsnummer**. Der Treiber setzt
`DRIVER_INITIALIZATION_DATA.Version = DXGKDDI_INTERFACE_VERSION`, das
System füllt `DXGKRNL_INTERFACE.Version`:

> „A positive integer that indicates the version of the functional
> interface implemented by the display port driver. **Version** can be
> one of the **`DXGKDDI_INTERFACE_VERSION_XXX`** values defined in
> **`D3dukmdt.h`**."⁵

Und die Tafel ist **additiv** gewachsen: jedes neue Mitglied ist mit
„Supported starting with WDDM 2.4 / 2.6 / 3.1" annotiert, die alten
stehen unverändert an ihrem Platz.⁵ Deshalb läuft ein WDDM-2.x-Treiber
unter einem Windows mit WDDM 3.x — er benutzt eben nur den 2.x-Umfang.

Die Zuordnung (Microsofts eigene Tabelle)⁶:

| WDDM | Windows |
|---|---|
| 1.0 | Vista |
| 1.1 | 7 |
| 1.2 | 8 (*„Windows 8 (WDDM 1.2) requires WDDM."*⁶) |
| 1.3 | 8.1 |
| 2.0 | 10 (1507) |
| 2.1 … 2.7 | 10 (1607 … 2004) |
| 3.0 | 11 (21H2) |
| 3.1 | 11 (22H2) |
| 3.2 | 11 (24H2) |

**Ehrlichkeitsvorbehalt:** Ich habe keine Microsoft-Seite gefunden, die
die Abwärtskompatibilität *als zugesicherte Politik* formuliert. Belegt
ist der Mechanismus (die `Version`-Felder, die additive Struktur), nicht
die Garantie. Für die *optionalen* Feature-Interfaces sagt Microsoft
sogar ausdrücklich das Gegenteil: „Feature interfaces **aren't required
to be backwards compatible** with older versions of the same
interface."⁷

### 1.4 Wie ein Treiber zur Laufzeit hineinkommt

Ein Kerneltreiber ist unter Windows **ein Dienst**:

> „If the service type is **SERVICE_KERNEL_DRIVER** … the name is the
> **driver object name** that the system uses to load the device
> driver."⁸

`CreateService` legt dafür einen Schlüssel unter
`HKLM\System\CurrentControlSet\Services` an.⁸ Die INF-Datei tut dasselbe
deklarativ über die `AddService`-Direktive.⁹ Geladen wird über den
Dienstverwalter (`StartService`) oder aus dem Kern heraus:

> „**ZwLoadDriver** dynamically loads a device or file system driver into
> the currently running system."¹⁰

`ZwLoadDriver` bekommt als Argument „a path to the driver's registry key,
`\Registry\Machine\System\CurrentControlSet\Services\<DriverName>`"¹⁰ —
und genau diesen Pfad reicht der Kern dann an `DriverEntry` weiter.¹¹

Dass `ntoskrnl` daraufhin das PE-Abbild in den Kernadressraum abbildet,
die Importe auflöst und `DriverEntry` ruft, folgt aus diesen Seiten, ist
dort aber **nicht wörtlich ausformuliert**. Ich führe es als sachlich
richtig, formal unbelegt.

### 1.5 Die Signaturpflicht

Die zentrale Regel, wörtlich:

> „**Starting with Windows 10, version 1607, Windows will not load any
> new kernel-mode drivers which are not signed by the Dev Portal.** To
> get your driver signed, first Register for the Windows Hardware Dev
> Center program. Note that an **EV code signing certificate is required
> to establish a dashboard account**."¹²

Wichtig und oft falsch wiedergegeben: das EV-Zertifikat baut nur den
Zugang zum Dashboard auf; die Signatur, die **zählt**, ist die von
Microsoft.¹² ¹³

Zwei Wege dorthin: WHQL/HLK mit vollen Testläufen (Produktion) oder
*Attestation Signing* ohne HLK-Tests, ausdrücklich „For testing on
Windows 10 client only systems".¹²

Ausnahmen, wörtlich:

> „Cross-signed drivers are still permitted if any of the following are
> true: The PC was **upgraded** from an earlier release of Windows to
> Windows 10, version 1607. **Secure Boot is off** in the BIOS. Driver
> was signed with an end-entity certificate **issued prior to July 29th
> 2015** …"¹²

Davor, seit Vista x64, galt das klassische Kernel Mode Code Signing:
Authenticode-Zertifikat plus Microsofts Cross-Zertifikat.¹² Cross-Signing
ist inzwischen abgeschafft: „Using cross certificates to sign kernel-mode
drivers is a violation of the Microsoft Trusted Root Program (TRP)
policy."¹⁴

Und es sind **zwei** Hürden, nicht eine: Code Integrity beim LADEN des
Abbilds, und die PnP-Signaturanforderung beim INSTALLIEREN des Pakets.¹⁵

*(HVCI habe ich nicht belegen können und lasse es deshalb weg.)*

### 1.6 Was daraus der eigentliche Grund ist

Herstellertreiber sind unter Windows möglich, weil **drei** Dinge
zusammenkommen — und keins davon allein genügt:

1. **EINE STABILE ABI.** `DXGKRNL_INTERFACE` und
   `DRIVER_INITIALIZATION_DATA` sind Verträge mit Fassungsnummern, die
   additiv wachsen. NVIDIA kann gegen WDDM 2.0 bauen und weiß, dass die
   Aufrufe in fünf Jahren noch an derselben Stelle stehen.
2. **EIN LADEFORMAT.** PE, ein Dienstschlüssel, ein Ladeaufruf, ein
   Einsprungpunkt (`DriverEntry`). Der Kern muss das Abbild zur Laufzeit
   abbilden und binden können.
3. **EINE SIGNATURKETTE.** Weil (1) und (2) zusammen bedeuten, dass
   fremder Programmtext in Ring 0 läuft, muss jemand dafür bürgen. Unter
   Windows ist dieser Jemand seit 1607 Microsoft selbst.

Nimmt man eins davon weg, bricht das Ganze: ohne (1) müsste jeder
Treiber je Windows-Version neu gebaut werden (das ist Linux, siehe
unten), ohne (2) müsste jeder Treiber einkompiliert werden (das war Osum
bis zu dieser Runde), ohne (3) wäre jeder heruntergeladene Treiber ein
zweiter Kern.

---

## 2. Wie Linux es macht — der Gegenentwurf

### 2.1 Was eine `.ko` ist

Kein Programm, sondern eine **ELF-Objektdatei vom Typ `ET_REL`** —
dasselbe, was ein Übersetzer als `.o` ausgibt, plus einer generierten
`<modul>.mod.o`. Der Kern prüft beim Laden Magie, Klasse, `e_type ==
ET_REL` und Architektur und antwortet sonst mit `-ENOEXEC`.¹⁶

Die Abschnitte, die zählen:

| Abschnitt | Inhalt |
|---|---|
| `.text`, `.data`, `.bss`, `.rodata` | Programmtext und Daten |
| `.init.text` / `.exit.text` | Ein- und Aussprung (der Init-Teil wird danach freigegeben) |
| `.modinfo` | `key=value`-Zeichenketten: `vermagic=`, `license=`, `depends=`, `srcversion=` … |
| `.gnu.linkonce.this_module` | die `struct module` des Moduls |
| `__ksymtab` / `__ksymtab_gpl` | was das Modul selbst ausführt |
| `__versions` | die CRCs der Symbole, die es BRAUCHT |
| `.rela.*` | die Relokationen (x86-64 nutzt RELA, also mit Addend) |

Belegt über `scripts/mod/modpost.c`, das die `.mod.c` erzeugt.¹⁷

### 2.2 Was `insmod` auslöst

Die Systemaufrufe sind `init_module()` und `finit_module()`. Die
Handbuchseite sagt, was der Kern dann tut:

> „performs any necessary symbol relocations, initializes module
> parameters to values provided by the caller, and then runs the module's
> init function."¹⁸

Im Kern (`kernel/module/main.c`) in dieser Reihenfolge: `elf_validity_check`
→ `check_modinfo` (vermagic!) → `layout_and_allocate` / `move_module`
(die `SHF_ALLOC`-Abschnitte in den Modulspeicher kopieren) →
`simplify_symbols` → `resolve_symbol` → `find_symbol` (jedes
undefinierte Symbol gegen die Kern-Symboltafel binden) →
`apply_relocations` → `apply_relocate_add` → `complete_formation` →
`do_init_module`.¹⁶

Auf x86-64 behandelt `apply_relocate_add` genau diese Arten:¹⁹

`R_X86_64_NONE`, `R_X86_64_64`, `R_X86_64_32` (unsigned, mit
Überlaufprüfung), `R_X86_64_32S` (signed), `R_X86_64_PC32` und
`R_X86_64_PLT32` (beide PC-relativ; PLT32 wird wie PC32 behandelt, weil
es im Kern keine PLT gibt), `R_X86_64_PC64`.

**Das ist Zeile für Zeile das, was `kernel/module.fi` dieser Runde tut** —
mit derselben Liste von Relokationsarten und derselben Reihenfolge. Der
Unterschied steht in Abschnitt 5.

### 2.3 `vermagic` — und warum es nicht reicht

`VERMAGIC_STRING` setzt sich zusammen aus `UTS_RELEASE` (der
Kernelversion), `"SMP "`, `"preempt "`/`"preempt_rt "`,
`"mod_unload "`, `"modversions "`, dem architekturspezifischen Teil und
dem RANDSTRUCT-Samen.²⁰

**Zwei verbreitete Irrtümer, die die Recherche ausräumt:** Die
gcc-Version steht dort **nicht** drin, und die Modulversion
(`MODULE_VERSION()`) auch nicht — die steht getrennt als `version=` in
`.modinfo`.²⁰

Passt es nicht:

```c
if (!same_magic(modmagic, vermagic, info->index.vers)) {
        pr_err("%s: version magic '%s' should be '%s'\n",
               info->name, modmagic, vermagic);
        return -ENOEXEC;
}
```
¹⁶

Und darüber liegt noch eine zweite Schicht, **`MODVERSIONS`**: je Symbol
eine CRC-Prüfsumme über die *erweiterte Typsignatur* (Rückgabetyp,
Argumenttypen, rekursiv aufgelöste Strukturen), erzeugt von `genksyms`.
Ändert sich ein Feld in einer Struktur, die in der Signatur vorkommt,
ändert sich die Summe, und das Modul wird abgelehnt:
`„%s: disagrees about version of symbol %s"`.²¹

### 2.4 Die Politik: es gibt keine stabile ABI

`Documentation/process/stable-api-nonsense.rst`, wörtlich:²²

> **„Linux does not have a binary kernel interface, nor does it have a
> stable kernel interface."**
>
> **„You think you want a stable kernel interface, but you really do not,
> and you don't even know it."**

Die drei Begründungen, wörtlich:²²

> „Depending on the version of the C compiler you use, different kernel
> data structures will contain different alignment of structures."
>
> „Depending on what kernel build options you select, a wide range of
> different things can be assumed by the kernel: different structures can
> contain different fields."
>
> „Linux runs on a wide range of different processor architectures. There
> is no way that binary drivers from one architecture will run on another
> properly."

Der vorgeschlagene Ausweg ist kein technischer, sondern ein sozialer:

> „Get your kernel driver into the main kernel tree … If your driver is
> in the tree, and a kernel interface changes, it will be fixed up by the
> person who did the kernel change in the first place."²²

Dazu die Lizenzgrenze: `EXPORT_SYMBOL` ist für alle,
`EXPORT_SYMBOL_GPL` nur für Module mit GPL-verträglicher
`MODULE_LICENSE`; eine fehlende oder unbekannte Lizenz gilt als
proprietär und setzt das Taint-Flag `P`.²³ ²⁴

### 2.5 Warum NVIDIAs Modul eine Zwischenschicht mitschleppt

NVIDIAs eigene Anleitung sagt es, wörtlich:²⁵

> „**The NVIDIA kernel module has a kernel interface layer that must be
> compiled specifically for each kernel. NVIDIA distributes the source
> code to this kernel interface layer.**"
>
> „After the correct kernel interface has been compiled, the kernel
> interface will be linked with the closed-source portion of the NVIDIA
> kernel module."

Der Aufbau: `nv-kernel.o_binary` ist der geschlossene, betriebssystem-
unabhängige Kern; er ruft nur NVIDIAs eigene Abstraktion (`nv_*`/`os_*`).
Darüber liegt quelloffener Klebecode, der diese Abstraktion auf echte
Kernel-Aufrufe abbildet und bei **jeder** Installation gegen die Header
des laufenden Kerns neu übersetzt wird. Dieselbe Zweiteilung findet sich
in den offenen Modulen: `kernel-open/` = „specific to the Linux kernel
version and configuration", `src/` = „independent of operating
system".²⁶

Der Beweis in Reinform ist `conftest.sh`: ein autoconf-artiges Skript,
das vor dem Übersetzen hunderte Miniprogramme gegen die Header des
Zielkerns baut, um herauszufinden, **ob** eine Funktion existiert,
**wie viele Argumente** sie nimmt und **welchen Typ** sie liefert.²⁷ Man
misst die ABI zur Bauzeit nach, weil man sie nicht wissen kann.

**Das ist die Antwort auf die Frage, warum es DKMS gibt.** Wäre die ABI
stabil, könnte NVIDIA ein einziges vorkompiliertes `nvidia.ko`
ausliefern.

---

## 3. Was für Osum daraus folgt — ehrlich

### 3.1 Ein Treiber von NVIDIA oder AMD wird es für Osum NIE geben

Das ist kein Pessimismus, es sind vier Gründe, die einzeln schon reichen:

1. **Der Treiber ist gegen eine andere ABI gebaut.** Ein
   Windows-Grafiktreiber ist ein PE-Abbild, das `DxgkInitialize` ruft und
   eine `DxgkDdi*`-Tafel füllt; ein Linux-Treiber ist ein `ET_REL`, das
   gegen `__ksymtab` gebunden wird. Osum hat weder das eine noch das
   andere, und beide nachzubauen hieße, Windows bzw. Linux nachzubauen.
2. **Niemand portiert ihn.** Die Recherche hat nach Herstellertreibern
   für Nischensysteme gesucht. Ergebnis: **NVIDIA ist die einzige
   Ausnahme, und nur für FreeBSD und Solaris** — belegt bis
   570.172.08 (FreeBSD)²⁸ und 545.23.06 (Solaris, Beta, 2023).²⁹ Für
   Haiku, ReactOS, SerenityOS und Redox gibt es **von keinem der beiden
   Hersteller irgendetwas**; alles, was dort läuft, ist
   Nachbauarbeit der jeweiligen Gemeinschaft.³⁰ Selbst AMD liefert für
   FreeBSD nichts Eigenes — `amdgpu` ist dort ein Gemeinschaftsport des
   Linux-Codes über eine Kompatibilitätsschicht (`linuxkpi`).³¹
   *(Ein Negativbeweis ist logisch nicht führbar; ich habe nach gezielter
   Suche keinen Hinweis auf das Gegenteil gefunden.)*
3. **Selbst ein perfekter Nachbau hilft bei NVIDIA nicht.** Ab Maxwell 2
   verlangt die Karte **signierte Firmware**. Dave Airlie, DRM-Betreuer
   bei Red Hat, dazu: **„you can't make it reclock, you can't make it go
   faster."**³² Man bekommt ein Bild, aber die Karte bleibt auf
   Starttakt. Ab Turing löst NVIDIAs GSP das — um den Preis, einen
   30–40 MB großen proprietären Blob in die Karte zu laden.³²
4. **Windows-Treiberkompatibilität ist selbst für ReactOS nur halb da.**
   ReactOS verfolgt das seit Jahren als ausdrückliches Ziel. Der
   offizielle Blog berichtet: Microsofts `BasicDisplay.sys` lädt, ein
   NVIDIA-Windows-7-Treiber liefert Bild „at full resolution and refresh
   rates" — aber **keine 3D-Beschleunigung, kein DirectX**, und
   fundamental: „XDDM is REQUIRED for WDDM, we need to continue to
   improve in this area."³³ *(Sekundärquellen behaupten „~90 % der
   XP/2003-Treiber laufen"; das ließ sich am Primärblog nicht
   verifizieren und wird hier nicht behauptet.)*

### 3.2 Was möglich ist — und nur das

**(a) Eigene Treiber, die nachgeladen statt einkompiliert werden.**
Genau das baut diese Runde. Es löst ein echtes Problem: heute entscheidet
`tools/build-kernel.sh`, welche Treiber Osum hat, und ein Gerät ohne
mitgebauten Treiber bleibt für immer stumm. Nach dieser Runde kann ein
Treiber ausgeliefert werden wie ein Programm.

**(b) Langfristig ein eigener, einfacher Modus-Setz-Treiber je
GPU-Familie.** Das ist der Weg, den alle Nischensysteme gehen, und er
hat eine klare Reihenfolge nach Aufwand:

| Ziel | Aufwand | Anmerkung |
|---|---|---|
| **Bochs/QEMU VBE** | eine Datei | Linux' ganzer Treiber liegt in `drivers/gpu/drm/tiny/bochs.c`.³⁴ **Osum hat das bereits** (`kernel/fb.fi`, Register 0x1CE/0x1CF³⁵). |
| **VMware SVGA II** | überschaubar | Register offen dokumentiert³⁶, in VirtualBox Standard für Linux-Gäste |
| **virtio-gpu** | mittel | braucht Virtqueues, spezifiziert³⁷ |
| **Intel GMA / i915** | groß, **je Generation neu** | Haiku führt dafür eine eigene Tabelle je Chipgeneration³⁸ |
| **AMD amdgpu** | sehr groß | deshalb PORTIERT FreeBSD den Linux-Code, statt neu zu schreiben³¹ |
| **NVIDIA modern** | scheitert nicht am Code, sondern an der Kryptografie³² | |

Was **nicht** möglich ist und wovon man auch nicht träumen soll: 3D-
Beschleunigung auf einer modernen Karte. Haiku hat eigene Modesetting-
Treiber für Intel und AMD — und rendert trotzdem in Software.³⁹ Redox
sagt es am offensten: **„Redox doesn't have GPU drivers yet"**, Ersatz
ist LLVMpipe, also OpenGL auf der CPU.⁴⁰

### 3.3 Der Satz, der Justins Frage direkt beantwortet

**Was er künftig nachladen kann:** eigene Osum-Treiber als `.omod`-Datei
— eine Netzkarte, eine Maus, eine Tonkarte, ein Speichertreiber, ein
einfacher Modus-Setz-Treiber für eine GPU-Familie. Aus seinem eigenen
Speicher (https://store.fleitec.com/), mit `opk` installiert, signiert
mit seinem eigenen Schlüssel. Das Bild „Treiber herunterladen" stimmt
also — nur ist der Absender er selbst.

**Was er nie nachladen kann:** einen Treiber von NVIDIA oder AMD. Nicht
weil Osum zu klein ist, sondern weil dieser Treiber gegen eine fremde
ABI gebaut ist, niemand ihn portiert, und die Karte selbst bei modernen
NVIDIA-Modellen ohne herstellersignierte Firmware nicht über den
Starttakt hinauskommt.

---

# TEIL 2 — DER ENTWURF

Zwei Wege führen zum Ziel „ein Treiber, der nicht im Kern steht".
Beide sind hier ausgearbeitet, mit Kosten und Risiken, und einer wird
empfohlen.

## 4. Weg A — Kernmodule (Ring 0)

### 4.1 Was zu bauen ist

1. **ELF-Objekt zur Laufzeit laden.** Die Datei von der Platte in einen
   Rahmenlauf lesen, die Abschnittstafel durchgehen, jedem Abschnitt mit
   `SHF_ALLOC` einen Platz im Abbild geben (ausgerichtet auf
   `sh_addralign`), `PROGBITS` kopieren, `NOBITS` nullen.
2. **Relokationen auflösen.** Jede `.rela.<abschnitt>`, deren Ziel im
   Abbild liegt. Fünf Arten reichen für das, was der Firn-Übersetzer
   erzeugt: `R_X86_64_64`, `PC32`, `PLT32`, `32`, `32S`. **Eine
   unbekannte Art muss die Datei ABWEISEN, nicht überspringen** — ein
   übersprungener Eintrag ist ein Loch im Programmtext, und der Absturz
   kommt dann irgendwann später an einer Stelle ohne Zusammenhang zur
   Ursache.
3. **Gegen eine exportierte Symboltafel binden.** Jedes undefinierte
   Symbol wird über seinen NAMEN in eine Adresse übersetzt. Die Tafel ist
   ausdrücklich und kurz — das ist der Unterschied zwischen einem Kern,
   dessen Innereien Vertragsfläche sind, und einem, dem sie gehören.
   Linux nennt das `EXPORT_SYMBOL`.
4. **Ein- und Aussprungpunkt.** Ein Name, den der Lader findet
   (`modul_init`/`modul_exit`), und der unter beiden Übersetzerstufen
   gleich heißt — in Firn geht das mit `#[export_c]`.
5. **Abhängigkeiten.** Linux hat `depends=` in `.modinfo` und
   `modprobe`, das den Baum auflöst. Für einen Prototypen unnötig; für
   einen Betrieb nötig, sobald ein Modul ein anderes braucht.
6. **Entladen.** Aussprung rufen, Tafel leeren, Rahmen zurückgeben — in
   dieser Reihenfolge. Wer die Rahmen zuerst zurückgibt, springt danach
   in fremden Speicher.

### 4.2 Die zwei Dinge, ohne die es fahrlässig wäre

**Eine versionierte Schnittstelle.** Ein Modul für den falschen Kern muss
ABGEWIESEN werden, nicht abstürzen. Das ist genau der Punkt, an dem
Windows seine WDDM-Fassungen hat und Linux `vermagic` + MODVERSIONS —
und der Unterschied zwischen „der Treiber lädt nicht" und „die Maschine
steht". Für Osum: eine Zahl im Kopf der Datei, verglichen gegen
`ksym.ABI`, **bevor** irgendetwas abgebildet wird.

Was diese Zahl erhöht, muss festgeschrieben sein, sonst ist sie
wertlos. Für Osum: (1) ein Name in der Ausfuhrtafel fällt weg oder
bekommt eine andere Signatur, (2) die Platznummern der Treibertafel
verschieben sich, (3) die Bedeutung eines Bereichs in `kdata`, den ein
Modul anfasst, ändert sich. Ein NEUER Name allein erhöht sie nicht — das
ist dieselbe additive Regel, die WDDM abwärtskompatibel hält.

**Eine Signaturprüfung.** Ed25519 liegt in Osum bereits
(`lib/crypto/ed25519.fi`, Runde UPDATE); Runde UPDATE benutzt es für
Systemabbilder, Runde BETRIEB für den Katalog, `kernel/user/opk.fi` für
jedes Paket. Ein unsigniertes Modul im Ring 0 ist ein Fremdkern — es hat
dieselben Rechte wie der Kern selbst, und kein Speicherschutz der Welt
steht dazwischen.

Der öffentliche Schlüssel muss **im Kernabbild** liegen, nicht in einer
Datei daneben. Wer die Platte schreiben kann, schriebe sonst beides.
Genau das steht auch in `orientstore/docs/KATALOG-FORMAT.md` Abschnitt 4
über den Speicherkatalog, und Windows macht es mit der Microsoft-Wurzel
nicht anders.

### 4.3 Was Weg A kostet

* **Ein Fehler im Modul tötet den Kern.** Das ist keine Schwäche des
  Entwurfs, das ist Ring 0. Es ist unter Windows und Linux genauso.
* **Kein W^X.** Osum setzt `EFER.NXE` nicht (nachgesehen in
  `kernel/arch/x86_64/boot.s`: gesetzt wird nur Bit 8, LME); die
  1-GiB-Identitätsabbildung besteht aus 2-MiB-Seiten mit `present |
  writable`. Jede beschreibbare Seite ist damit ausführbar. Für den
  Modullader ist das bequem — er kann in einen frisch geholten Rahmen
  schreiben und hineinspringen — und es ist zugleich eine offene Kante,
  die benannt gehört.
* **Der Lader selbst wächst in den Kern hinein.** Ein ELF-Parser, ein
  Relokationsrechner und eine Ed25519-Prüfung sind Programmtext in Ring 0,
  der auf fremde Daten losgelassen wird. Jede Grenze darin muss als
  Subtraktion geschrieben sein: unter `profile kernel` ist `+` geprüft
  und ruft bei Überlauf `osum_panic` — aus einer geladenen Datei heraus
  wäre das ein gehaltener Rechner statt einer Abweisung. Dieselbe Regel
  gilt seit Runde K1 in `kernel/elf.fi`.

## 5. Weg B — Treiber im Ring 3

### 5.1 Was zu bauen ist

Den MMIO-Bereich und die Unterbrechung an ein gewöhnliches Programm
durchreichen. Linux hat dafür zwei Bauformen, und beide sind gut
dokumentiert.

**UIO** ist die einfache. Der Treiber im Kern (`uio_pci_generic`) tut nur
zweierlei: er maskiert und quittiert die Unterbrechung und gibt die BARs
zum Abbilden frei. Die Zustellung ist bewusst primitiv:

> „A blocking `read()` from `/dev/uioX` will return as soon as an
> interrupt occurs."⁴¹
>
> „The signed 32 bit integer read is the interrupt count of your device.
> If the value is one more than the value you read the last time,
> everything is OK."⁴¹

Also kein Signal, kein Rückruf, sondern ein Zähler — verlorene
Unterbrechungen erkennt man an der Lücke. Das MMIO kommt per `mmap`, wobei
der Versatz als Index missbraucht wird: `offset = N * getpagesize()`.⁴¹
Danach ist das BAR ein gewöhnlicher Zeiger im Prozessadressraum.

**VFIO** ist die sichere. Es fügt hinzu: IOMMU-erzwungene DMA-Isolation,
MSI/MSI-X, geregelten Zugriff auf den PCI-Konfigurationsraum, und
Nutzung ohne Dauer-root.⁴²

### 5.2 Der Preis, ehrlich benannt

**Mehr Kontextwechsel.** Jede Unterbrechung wird zu einem Aufwachen eines
Ring-3-Prozesses. Die Praxis umgeht das, indem sie Unterbrechungen ganz
abschafft: DPDKs Treiber sind „designed to work without asynchronous,
interrupt-based signaling mechanisms", und in den Beispielen heißt es,
das interruptgetriebene Modell sei zwar stromsparend, habe aber
„additional performance overhead".⁴³ SPDK nennt als Gewinn „avoids
syscalls and enables zero-copy access from the application" und
„Polling hardware for completions instead of relying on interrupts".⁴⁴
Der Preis dafür steht daneben: ein Prozessorkern läuft dauerhaft auf
100 %, auch bei null Paketen.

**DMA IST DAS LOCH, UND ES GEHÖRT BENANNT.** Die MMU schützt vor dem,
was die CPU im Treiberprozess tut. DMA geht an der MMU vorbei. Der Satz
aus Linux' eigener VFIO-Dokumentation:

> „DMA is by far the most critical aspect for maintaining a secure
> environment as allowing a device read-write access to system memory
> imposes the greatest risk to the overall system integrity."⁴²

Und über UIO:

> UIO-artige Ansätze haben „no notion of IOMMU protection, limited
> interrupt support, and requires root privileges to access things like
> PCI configuration space."⁴²

DPDK sagt es noch direkter: „Using UIO drivers is inherently unsafe due
to this method lacking IOMMU protection, and can only be done by root
user."⁴⁵ Für UIO-Bindung empfiehlt die DPDK-Anleitung sogar
ausdrücklich, die IOMMU **abzuschalten** oder in den Durchreichmodus zu
stellen.⁴⁵

**Konkret für Osum:** Ein Ring-3-Treiber ohne IOMMU kann die Karte
anweisen, an jede physische Adresse zu schreiben — auch in den Kern.
Das heißt: **ein Ring-3-Treiber ohne IOMMU ist nicht sicherer als ein
Ring-0-Modul, er sieht nur so aus.** Was er wirklich bringt, ist nicht
Sicherheit, sondern **Verfügbarkeit**: ein abgestürzter Treiber reißt
den Kern nicht mit und kann neu gestartet werden. Genau so machen es die
Mikrokerne — QNX („If a component should fail, it can usually be
automatically restarted without affecting other components or the
kernel"⁴⁶), MINIX 3 mit seinem Reincarnation Server⁴⁷ und Fuchsia mit
`host_restart_on_crash`.⁴⁸

Und seL4 sagt als einziges offen, wo die Garantie endet:

> „The formal verification of seL4 assumes that the MMU has complete
> control over memory, which means the proof assumes that **DMA is
> off**."⁴⁹
>
> „You can still use DMA devices safely, but you have to separately
> assure that they are well-behaved … drivers and hardware for DMA
> devices need to be **trusted**."⁴⁹

*(Am ehrlichsten hat das Fuchsia gelöst: dort ist das DMA-Recht ein
eigenes Kernobjekt, das BTI, das den Hardware-Transaktionsbezeichner der
IOMMU trägt.⁴⁸ Das ist der Entwurf, den Osum eines Tages haben will —
aber er setzt eine IOMMU voraus, die Osum heute nicht anspricht.)*

*(Am Rande, weil es die dritte Möglichkeit zeigt: macOS geht seit
10.15 den Ring-3-Weg mit DriverKit — „Drivers built with DriverKit run
in user space, rather than as kernel extensions, for improved system
security and stability."⁵⁰ Der Preis ist nicht technisch, sondern
politisch: für einen DEXT braucht man ein von Apple einzeln beantragtes
Entitlement.⁵¹ Die Torwächterrolle wandert vom Kern zur
Zertifizierungsstelle.)*

## 6. Welcher Weg für welche Geräteart

| Gerät | Weg | Grund |
|---|---|---|
| **Netzkarte** | Ring 3 ist ein guter Kandidat | Ein Netz, das für zwei Sekunden weg ist, ist ein Ärgernis; ein Kern, der weg ist, ist ein Datenverlust. Der Datenweg ist ohnehin gepuffert, und DPDK zeigt, dass es sogar SCHNELLER sein kann. |
| **Speichertreiber, der die Wurzel trägt** | **Ring 0, keine Debatte** | Der Treiber wird gebraucht, bevor es einen Ring 3 gibt. Und ein Neustart hilft nicht: das Dateisystem, das darüber liegt, hat halb geschriebene Blöcke. Ein Speichertreiber ist kein Dienst, er ist ein Fundament. |
| **Maus, Tastatur** | egal, Ring 0 ist einfacher | Winzige Datenmengen, kein DMA, kein Verfügbarkeitsproblem. |
| **Tonkarte** | Ring 3 ideal | Aussetzer sind hörbar, aber harmlos. DMA-Puffer sind fest und klein. |
| **GPU-Modus-Setzen** | Ring 0 | Es passiert einmal beim Start; der Rahmenpuffer ist danach eine Abbildung. |

## 7. Die Empfehlung

**Weg A — Kernmodule mit versionierter Schnittstelle und
Ed25519-Signaturpflicht.**

Vier Gründe, in dieser Reihenfolge:

1. **Weg B ist heute in Osum nicht ehrlich machbar.** Es gibt keinen
   IOMMU-Treiber. Ein Ring-3-Treiber ohne IOMMU hat volle DMA-Gewalt
   über den ganzen Speicher — die Ring-3-Grenze wäre Zierat, und das
   wäre schlimmer als kein Schutz, weil es nach Schutz aussieht.
2. **Weg A löst das Problem, das wirklich da ist.** Die Frage war nicht
   „wie mache ich Treiber sicherer", sondern „wie bekomme ich einen
   Treiber ins System, ohne den Kern neu zu bauen". Genau das leistet A,
   und B leistet es zusätzlich noch nicht besser.
3. **Weg A liegt auf dem, was Osum schon hat.** Der Firn-Übersetzer
   erzeugt bereits `ET_REL`-Objektdateien mit genau vier
   Relokationsarten; `kernel/elf.fi` beweist seit Runde K1, dass dieser
   Kern ELF lesen und dabei alles Falsche abweisen kann;
   `lib/crypto/ed25519.fi` liegt seit Runde UPDATE da. Es fehlt der
   Lader, nicht das Fundament.
4. **Weg B bleibt danach offen und wird leichter.** Wer Module laden
   kann, kann später ein Modul laden, das die IOMMU aufsetzt — und
   DANACH ist Weg B ehrlich. Andersherum geht es nicht.

**Was das ausdrücklich NICHT heißt:** dass Ring 0 sicher ist. Der
Prototyp misst das Gegenteil — ein absichtlich verdorbenes, aber
korrekt signiertes Modul bringt den Kern um (`docs/RUNDE-MODUL.md`,
Abschnitt zur gemessenen Grenze). Die Signatur ist der einzige Riegel,
den es an dieser Tür gibt, und deshalb ist sie Pflicht und nicht Kür.

---

## Quellen

1. [Microsoft Basic Display Driver](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/microsoft-basic-display-driver)
2. [DirectX WARP](https://learn.microsoft.com/en-us/windows/win32/direct3darticles/directx-warp)
3. [WDDM Architecture](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/windows-vista-and-later-display-driver-model-architecture)
4. [DxgkInitialize](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/dispmprt/nf-dispmprt-dxgkinitialize)
5. [DXGKRNL_INTERFACE](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/dispmprt/ns-dispmprt-_dxgkrnl_interface)
6. [WDDM Design Guide (Versionstabelle)](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/windows-vista-display-driver-model-design-guide)
7. [Querying WDDM Feature Support](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/querying-wddm-feature-support-and-enablement)
8. [CreateService (winsvc.h)](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-createservicea)
9. [INF AddService Directive](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/inf-addservice-directive)
10. [ZwLoadDriver](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/wdm/nf-wdm-zwloaddriver)
11. [DriverEntry's Optional Responsibilities](https://learn.microsoft.com/en-us/windows-hardware/drivers/kernel/driverentry-s-optional-responsibilities)
12. [Kernel-Mode Code Signing Policy](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/kernel-mode-code-signing-policy--windows-vista-and-later-)
13. [Attestation Sign Windows Drivers](https://learn.microsoft.com/en-us/windows-hardware/drivers/dashboard/code-signing-attestation)
14. [Cross-Certificates for Kernel Mode Code Signing](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cross-certificates-for-kernel-mode-code-signing)
15. [PnP device installation signing requirements](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/pnp-device-installation-signing-requirements--windows-vista-and-later-)
16. [kernel/module/main.c](https://github.com/torvalds/linux/blob/master/kernel/module/main.c)
17. [scripts/mod/modpost.c](https://github.com/torvalds/linux/blob/master/scripts/mod/modpost.c)
18. [init_module(2) / finit_module(2)](https://man7.org/linux/man-pages/man2/init_module.2.html)
19. [arch/x86/kernel/module.c](https://github.com/torvalds/linux/blob/master/arch/x86/kernel/module.c)
20. [include/linux/vermagic.h](https://github.com/torvalds/linux/blob/master/include/linux/vermagic.h)
21. [kernel/module/version.c](https://github.com/torvalds/linux/blob/master/kernel/module/version.c)
22. [Documentation/process/stable-api-nonsense.rst](https://docs.kernel.org/process/stable-api-nonsense.html)
23. [include/linux/export.h](https://github.com/torvalds/linux/blob/master/include/linux/export.h)
24. [Tainted kernels](https://www.kernel.org/doc/html/latest/admin-guide/tainted-kernels.html)
25. [NVIDIA README — Installing the NVIDIA Driver](https://download.nvidia.com/XFree86/Linux-x86/384.59/README/installdriver.html)
26. [NVIDIA/open-gpu-kernel-modules](https://github.com/NVIDIA/open-gpu-kernel-modules)
27. [conftest.sh](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/main/kernel-open/conftest.sh)
28. [NVIDIA FreeBSD Display Driver 570.172.08](https://www.nvidia.com/en-us/drivers/details/249293/)
29. [NVIDIA Solaris Display Driver 545.23.06](https://nvidia.com/en-us/drivers/details/212965)
30. [Haiku NVIDIA-Treiber (Community, Rudolf Cornelissen)](https://github.com/haiku/haiku/blob/master/src/add-ons/kernel/drivers/graphics/nvidia/UPDATE.html)
31. [freebsd/drm-kmod](https://github.com/freebsd/drm-kmod) · [FreshPorts graphics/drm-kmod](https://www.freshports.org/graphics/drm-kmod/)
32. [LWN — NVIDIA and nouveau (Dave Airlie)](https://lwn.net/Articles/910343/)
33. [ReactOS Blog — Investigating WDDM](https://reactos.org/blogs/investigating-wddm/)
34. [drivers/gpu/drm/tiny/bochs.c](https://elixir.bootlin.com/linux/v6.12.6/source/drivers/gpu/drm/tiny/bochs.c)
35. [OSDev — Bochs VBE Extensions](https://wiki.osdev.org/Bochs_VBE_Extensions) · [QEMU Standard VGA](https://www.qemu.org/docs/master/specs/standard-vga.html)
36. [VMware SVGA Device Developer Kit](https://vmware-svga.sourceforge.net/)
37. [QEMU — VirtIO GPU](https://www.qemu.org/docs/master/system/devices/virtio/virtio-gpu.html)
38. [Haiku — Intel video hardware generations](https://www.haiku-os.org/docs/develop/drivers/intel_extreme/generations.html)
39. [Haiku GSoC 2017 — 3D Hardware Acceleration](https://www.haiku-os.org/blog/vivek/2017-05-05_gsoc_2017_3d_hardware_acceleration_in_haiku)
40. [Redox Book — Graphics and Windowing](https://doc.redox-os.org/book/graphics-windowing.html)
41. [Linux UIO HOWTO](https://www.kernel.org/doc/html/latest/driver-api/uio-howto.html)
42. [Linux VFIO](https://www.kernel.org/doc/html/latest/driver-api/vfio.html)
43. [DPDK Overview](https://doc.dpdk.org/guides/prog_guide/overview.html)
44. [SPDK About](https://spdk.io/doc/about.html)
45. [DPDK Linux Drivers (UIO/VFIO)](https://doc.dpdk.org/guides/linux_gsg/linux_drivers.html)
46. [QNX Neutrino Microkernel](https://www.qnx.com/developers/docs/6.5.0SP1/neutrino/sys_arch/kernel.html)
47. [MINIX 3 Reliability](https://wiki.minix3.org/doku.php?id=www:documentation:reliability)
48. [Fuchsia — Bus Transaction Initiator](https://fuchsia.dev/fuchsia-src/reference/kernel_objects/bus_transaction_initiator) · [Driver Framework](https://fuchsia.dev/fuchsia-src/concepts/drivers/driver_framework)
49. [seL4 FAQ](https://sel4.systems/About/FAQ.html)
50. [Apple — DriverKit security for macOS](https://support.apple.com/guide/security/driverkit-security-for-macos-secd0a47c14c/web)
51. [Apple — Kernel Extensions / Entitlement](https://developer.apple.com/support/kernel-extensions/)

**Was in diesem Dokument NICHT belegt ist** und deshalb auch nicht
behauptet wird: die Windows-Version, in der der Basic Display Driver
eingeführt wurde; eine ausdrückliche Microsoft-Zusage zur
WDDM-Abwärtskompatibilität; die Zuordnung WDDM 2.8/2.9 zu einem
Windows-Release; das PE-Abbildungsdetail in `ntoskrnl`; die
HVCI-Anforderungen; die genaue Zeilenzahl von `bochs.c`; die in
Sekundärquellen kursierende Zahl „~90 % der XP-Treiber laufen auf
ReactOS"; ob NVIDIA seine Solaris-Linie eingestellt hat. Ein
Negativbeweis („NVIDIA hat NIE einen Treiber für Haiku veröffentlicht")
ist logisch nicht führbar — es wurde gezielt gesucht und nichts
gefunden.
