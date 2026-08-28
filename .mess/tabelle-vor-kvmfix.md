| Abschnitt | TCG | KVM | Faktor | TCG-Ergebnis | KVM-Ergebnis |
|---|---:|---:|---:|---|---|
|  2. freistehend uebersetzen: profile kernel, I (`freestanding`) | 40.5 s | 40.5 s | = | gruen, 41 Zusagen | gruen, 41 Zusagen |
|  3. std.core im Kernel: die Bibliothek ohne Al (`core`) | 62.6 s | 62.5 s | = | gruen, 46 Zusagen | gruen, 46 Zusagen |
|  4. der Kern laeuft: Aufgaben, Adressraeume, S (`kernel`) | 94.8 s | 65.9 s | 1.4x | gruen, 176 Zusagen | **ROT**, 117 Zusagen |
|  5. ein Programm von der Platte: ELF-Lader, ex (`osum`) | 71.4 s | 90.8 s | 0.79x | gruen, 130 Zusagen | **ROT**, 38 Zusagen |
|  6. der Kernel liest seine Maschine: PCI, APIC (`pci`) | 93.6 s | 58.6 s | 1.6x | gruen, 98 Zusagen | **ROT**, 52 Zusagen |
|  7. die POSIX-Schicht und die libc (tools/posi (`posix`) | 52.2 s | 45.1 s | 1.2x | gruen, 134 Zusagen | **ROT**, 54 Zusagen |
|  8. vier Prozessoren, und die Sperre, die eine (`smp`) | 77.5 s | 79.4 s | = | gruen, 59 Zusagen (tcg-fest) | gruen, 59 Zusagen (tcg-fest) |
|  9. ein Userland: eine Shell, 25 Werkzeuge, Ro (`userland`) | 109.7 s | 98.8 s | 1.1x | gruen, 91 Zusagen | **ROT**, 15 Zusagen |
| 10. Handles statt Umgebungsautoritaet: die Cap (`caps`) | 46.7 s | 42.3 s | 1.1x | gruen, 67 Zusagen | **ROT**, 36 Zusagen |
| 11. der Multiboot-Kopf verlangt einen Bildschi (`boot`) | 43.0 s | 42.5 s | = | gruen, 20 Zusagen | **ROT**, 18 Zusagen |
| 12. der Bildschirm: Rahmenpuffer, Textkonsole, (`gfx`) | 93.2 s | 156.0 s | 0.60x | gruen, 76 Zusagen | **ROT**, 39 Zusagen |
| 13. was jedes Unix-Programm voraussetzt: Signa (`unix`) | 20.5 s | 12.5 s | 1.6x | gruen, 107 Zusagen | **ROT**, 32 Zusagen |
| 14. das Netz: virtio-net, der Stack aus K3, St (`net`) | 318.8 s | 344.0 s | 0.93x | **ROT**, 73 Zusagen | **ROT**, 24 Zusagen |
| 15. die Schutzbits und das Boot-Modul: SMEP, S (`guard`) | 74.7 s | 54.5 s | 1.4x | gruen, 55 Zusagen | **ROT**, 30 Zusagen |
| 16. man kann darauf arbeiten: ein Editor, zwan (`k11`) | 168.8 s | 602.7 s | 0.28x | gruen, 85 Zusagen | **ROT**, 18 Zusagen |
| 17. die Oberflaeche: Maus, Fensterserver, True (`wm`) | 129.1 s | 409.6 s | 0.32x | gruen, 103 Zusagen | **ROT**, 31 Zusagen |
| 18. ein Wirt fuer fremde Prozessoren: AMD-V, v (`hv`) | 113.3 s | 113.8 s | = | gruen, 114 Zusagen (tcg-fest) | gruen, 114 Zusagen (tcg-fest) |
| 19. Benutzer, Rechte und der erste Prozess: ui (`k13`) | 161.7 s | 59.9 s | 2.7x | gruen, 99 Zusagen | **ROT**, 39 Zusagen |
| 20. die VFS-Schicht und die fremden Dateisyste (`k14`) | 127.3 s | 83.4 s | 1.5x | **ROT**, 151 Zusagen | **ROT**, 49 Zusagen |
| 21. der Uebersetzer laeuft auf dem System selb (`k16`) | 83.2 s | 68.6 s | 1.2x | **ROT**, 58 Zusagen | **ROT**, 22 Zusagen |
| 22. Widgets und der Dateimanager: eine Bibliot (`k15`) | 843.3 s | 518.0 s | 1.6x | gruen, 252 Zusagen | **ROT**, ? |
| 25. der Fensterbaum: Kacheln, Reiter, Drehen - (`tiling`) | 93.9 s | 124.4 s | 0.76x | gruen, 68 Zusagen | **ROT**, 13 Zusagen |
| 24. Energie und Leistung: drei Profile, Ruhezu (`k18`) | 111.2 s | 130.9 s | 0.85x | gruen, 170 Zusagen | **ROT**, 49 Zusagen |
| 25. die zweite Maschine: AArch64 auf qemu -M v (`arm`) | 47.9 s | 47.9 s | = | gruen, 48 Zusagen (tcg-fest) | gruen, 48 Zusagen (tcg-fest) |
| 23. USB: xHCI, Aufzaehlung, Tastatur, Maus und (`k17`) | 134.5 s | 290.9 s | 0.46x | gruen, 158 Zusagen | **ROT**, 59 Zusagen |
| 26. Der Bildschirm, zum zweiten Mal: Moduslist (`display`) | 119.4 s | 180.3 s | 0.66x | gruen, 145 Zusagen | **ROT**, 65 Zusagen |
| 27. Marken statt Farben: hell, dunkel, automat (`theme`) | 210.8 s | 227.8 s | 0.93x | gruen, ? | **ROT**, ? |
| 25. das Symbolsystem: eine Schrift fuer die Ob (`icons`) | 111.4 s | 112.6 s | = | **ROT**, ? | **ROT**, ? |
| 25. eine Netzsicht je Prozess: real, filtered, (`netview`) | 652.1 s | 1285.0 s | 0.51x | gruen, 195 Zusagen | **ROT**, 16 Zusagen |
| 26. wer wieviel verbraucht, und die Verbindung (`netmon`) | 879.0 s | -- | -- | gruen, 76 Zusagen | -- |
| **Summe der Abschnitte** | **5186 s** | **5449 s** | **1.0x** | | |


UNTER KVM ROT GEWORDEN (20): kernel, osum, pci, posix, userland, caps, boot, gfx, unix, guard, k11, wm, k13, k15, tiling, k18, k17, display, theme, netview
| Abschnitt | TCG | KVM | Faktor | TCG-Ergebnis | KVM-Ergebnis |
|---|---:|---:|---:|---|---|
| 25. der Tunnel: WireGuard, AmneziaWG, SOCKS5 u (`tunnel`) | 263.0 s | 766.2 s | 0.34x | gruen, ? | **ROT**, ? |
| 26. der Tunnel als PAKET: was er kostet, wenn (`tunnelkosten`) | 632.3 s | 493.3 s | 1.3x | gruen, ? | **ROT**, ? |
| 27. installieren, benutzen, entfernen -- und n (`tunnelpakete`) | 276.4 s | 1.7 s | 165.6x | **ROT**, ? (tcg-fest) | **ROT**, ? (tcg-fest) |
| 25. Diebstahl: Geraeteidentitaet, Sicherung, S (`tresor`) | 119.8 s | 39.9 s | 3.0x | gruen, 220 Zusagen | **ROT**, 62 Zusagen |
| 25. Akkuanalyse je Programm: die gemessene Ges (`powermon`) | 164.7 s | 96.0 s | 1.7x | gruen, 121 Zusagen | **ROT**, 30 Zusagen |
| 26. wer wieviel verbraucht, und die Verbindung (`netmon`) | -- | 403.4 s | -- | -- | **ROT**, 11 Zusagen |
| **Summe der Abschnitte** | **1456 s** | **1801 s** | **0.8x** | | |

TCG-Bilanz: 5 Abschnitte bestanden, 1 FEHLGESCHLAGEN (350 Zusagen)
KVM-Bilanz: 1 Abschnitte bestanden, 6 FEHLGESCHLAGEN (112 Zusagen)

UNTER KVM ROT GEWORDEN (4): tunnel, tunnelkosten, tresor, powermon
