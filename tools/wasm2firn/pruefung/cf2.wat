(module
  (import "wasi_snapshot_preview1" "fd_write" (func $fw (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit" (func $ex (param i32)))
  (memory 1)
  (export "memory" (memory 0))
  (data (i32.const 500) "OK\n")
  (data (i32.const 510) "FEHLER\n")
  (func $p (param $x i32) (param $y i32)
    (if (i32.eq (local.get $x) (local.get $y))
      (then (i32.store (i32.const 100) (i32.const 500)) (i32.store (i32.const 104) (i32.const 3)))
      (else (i32.store (i32.const 100) (i32.const 510)) (i32.store (i32.const 104) (i32.const 7))))
    (drop (call $fw (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 120))))

  ;; GENAU DIE FORM VON f175: block{ block{ br_if 0; ...; br 1 } REST1 } REST2
  (func $g (param $n i32) (result i32) (local $r i32)
    (block $a
      (block $b
        (br_if $b (local.get $n))     ;; n!=0 -> raus aus b, weiter bei REST1
        (local.set $r (i32.const 10))
        (br $a))                      ;; sonst: raus aus a, REST1 UEBERSPRINGEN
      (local.set $r (i32.add (local.get $r) (i32.const 1))))   ;; REST1
    (local.set $r (i32.add (local.get $r) (i32.const 100)))    ;; REST2
    (local.get $r))

  ;; drei Ebenen mit Rest auf jeder
  (func $h (param $n i32) (result i32) (local $r i32)
    (block $a
      (block $b
        (block $c
          (br_if $c (i32.eq (local.get $n) (i32.const 0)))
          (br_if $b (i32.eq (local.get $n) (i32.const 1)))
          (br $a))
        (local.set $r (i32.or (local.get $r) (i32.const 1))))   ;; nach c
      (local.set $r (i32.or (local.get $r) (i32.const 2))))     ;; nach b
    (i32.or (local.get $r) (i32.const 4)))                      ;; nach a

  (func (export "_start")
    (call $p (call $g (i32.const 1)) (i32.const 101))   ;; br_if b -> REST1+REST2
    (call $p (call $g (i32.const 0)) (i32.const 110))   ;; br a -> nur REST2
    (call $p (call $h (i32.const 0)) (i32.const 7))     ;; c: 1|2|4
    (call $p (call $h (i32.const 1)) (i32.const 6))     ;; b: 2|4
    (call $p (call $h (i32.const 5)) (i32.const 4))     ;; a: 4
    (call $ex (i32.const 0))))
