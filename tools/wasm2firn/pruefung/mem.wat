(module
  (import "wasi_snapshot_preview1" "fd_write" (func $fw (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit" (func $ex (param i32)))
  (memory 1)
  (export "memory" (memory 0))
  (data (i32.const 500) "OK\n")
  (data (i32.const 510) "FEHLER\n")
  (data (i32.const 700) "abcdefgh")
  (func $pruef (param $x i32) (param $y i32)
    (if (i32.eq (local.get $x) (local.get $y))
      (then (i32.store (i32.const 100) (i32.const 500)) (i32.store (i32.const 104) (i32.const 3)))
      (else (i32.store (i32.const 100) (i32.const 510)) (i32.store (i32.const 104) (i32.const 7))))
    (drop (call $fw (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 120))))
  (func (export "_start")
    ;; alle Breiten schreiben und zurueckleisen
    (i64.store (i32.const 800) (i64.const 0x0123456789abcdef))
    (call $pruef (i32.load (i32.const 800)) (i32.const 0x89abcdef))
    (call $pruef (i32.load (i32.const 804)) (i32.const 0x01234567))
    (call $pruef (i32.load8_u (i32.const 800)) (i32.const 0xef))
    (call $pruef (i32.load16_u (i32.const 800)) (i32.const 0xcdef))
    (i32.store16 (i32.const 820) (i32.const 0x1234))
    (call $pruef (i32.load16_u (i32.const 820)) (i32.const 0x1234))
    (i32.store8 (i32.const 830) (i32.const 0xff))
    (call $pruef (i32.load8_s (i32.const 830)) (i32.const -1))
    ;; UNAUSGERICHTET (RUNDE SCHLEUSE-3): die Laufzeit liest/schreibt
    ;; 16/32/64 Bit jetzt in EINEM Zugriff statt byteweise. WASM erlaubt
    ;; ausdruecklich unausgerichtete Adressen -- also wird genau das
    ;; hier geprueft, sonst faellt es erst bei SQLite auf.
    (i32.store (i32.const 1003) (i32.const 0x11223344))
    (call $pruef (i32.load (i32.const 1003)) (i32.const 0x11223344))
    (call $pruef (i32.load8_u (i32.const 1003)) (i32.const 0x44))
    (call $pruef (i32.load8_u (i32.const 1006)) (i32.const 0x11))
    (i64.store (i32.const 1015) (i64.const 0x0102030405060708))
    (call $pruef (i32.load (i32.const 1015)) (i32.const 0x05060708))
    (call $pruef (i32.load (i32.const 1019)) (i32.const 0x01020304))
    (i32.store16 (i32.const 1031) (i32.const 0xbeef))
    (call $pruef (i32.load16_u (i32.const 1031)) (i32.const 0xbeef))
    (call $pruef (i32.load8_u (i32.const 1032)) (i32.const 0xbe))
    ;; Vorzeichen bei unausgerichteter Adresse
    (i32.store16 (i32.const 1041) (i32.const 0xfffe))
    (call $pruef (i32.load16_s (i32.const 1041)) (i32.const -2))
    ;; memory.copy mit Ueberlappung nach vorn
    (memory.copy (i32.const 701) (i32.const 700) (i32.const 4))
    (call $pruef (i32.load8_u (i32.const 701)) (i32.const 97))
    (call $pruef (i32.load8_u (i32.const 704)) (i32.const 100))  ;; memmove-Verhalten: d ruecknach
    ;; memory.fill
    (memory.fill (i32.const 900) (i32.const 65) (i32.const 4))
    (call $pruef (i32.load8_u (i32.const 903)) (i32.const 65))
    (call $pruef (i32.load8_u (i32.const 904)) (i32.const 0))
    ;; memory.size / grow
    (call $pruef (memory.size) (i32.const 1))
    (call $pruef (memory.grow (i32.const 1)) (i32.const 1))
    (call $pruef (memory.size) (i32.const 2))
    (call $ex (i32.const 0))))
