(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fw (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit" (func $ex (param i32)))
  (memory 1)
  (export "memory" (memory 0))
  (data (i32.const 500) "OK\n")
  (data (i32.const 510) "FEHLER\n")
  (func $pruef (param $a i32) (param $b i32)
    (if (i32.eq (local.get $a) (local.get $b))
      (then (i32.store (i32.const 100) (i32.const 500))
            (i32.store (i32.const 104) (i32.const 3)))
      (else (i32.store (i32.const 100) (i32.const 510))
            (i32.store (i32.const 104) (i32.const 7))))
    (drop (call $fw (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 120))))

  ;; br 1 aus einem inneren block heraus, danach MUSS der Rest des
  ;; aeusseren Blocks uebersprungen werden
  (func $t1 (result i32) (local $x i32)
    (block $aussen
      (block $innen
        (br $aussen))          ;; springt an aussen vorbei
      (local.set $x (i32.const 111)))   ;; darf NICHT laufen
    (local.get $x))            ;; erwartet 0

  ;; br_if mit Wert auf dem Stapel
  (func $t2 (result i32)
    (block $b (result i32)
      (i32.const 7)
      (br_if $b (i32.const 1))
      (drop) (i32.const 9)))   ;; erwartet 7

  ;; loop mit br zurueck
  (func $t3 (result i32) (local $i i32) (local $s i32)
    (loop $l
      (local.set $s (i32.add (local.get $s) (local.get $i)))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br_if $l (i32.lt_s (local.get $i) (i32.const 5))))
    (local.get $s))            ;; 0+1+2+3+4 = 10

  ;; br_table
  (func $t4 (param $n i32) (result i32)
    (block $d (block $c (block $b (block $a
      (br_table $a $b $c $d (local.get $n)))
      (return (i32.const 10)))
      (return (i32.const 20)))
      (return (i32.const 30)))
    (i32.const 40))

  ;; drei Ebenen: br 2 ueberspringt zwei Bloecke
  (func $t5 (result i32) (local $x i32)
    (block $a
      (block $b
        (block $c
          (br $a))
        (local.set $x (i32.const 1)))
      (local.set $x (i32.add (local.get $x) (i32.const 2))))
    (local.get $x))            ;; erwartet 0

  (func (export "_start")
    (call $pruef (call $t1) (i32.const 0))
    (call $pruef (call $t2) (i32.const 7))
    (call $pruef (call $t3) (i32.const 10))
    (call $pruef (call $t4 (i32.const 0)) (i32.const 10))
    (call $pruef (call $t4 (i32.const 1)) (i32.const 20))
    (call $pruef (call $t4 (i32.const 2)) (i32.const 30))
    (call $pruef (call $t4 (i32.const 9)) (i32.const 40))
    (call $pruef (call $t5) (i32.const 0))
    (call $ex (i32.const 0))))
