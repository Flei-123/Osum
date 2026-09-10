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

  ;; if MIT Ergebnis, br aus einem if heraus, if ohne else
  (func $a (param $n i32) (result i32)
    (if (result i32) (local.get $n) (then (i32.const 5)) (else (i32.const 9))))
  (func $b (param $n i32) (result i32) (local $r i32)
    (block $out
      (if (local.get $n) (then (local.set $r (i32.const 1)) (br $out)))
      (local.set $r (i32.const 2)))
    (local.get $r))
  ;; br aus dem then-Zweig zwei Ebenen hoch
  (func $c (param $n i32) (result i32) (local $r i32)
    (block $x
      (block $y
        (if (local.get $n) (then (br $x)))
        (local.set $r (i32.or (local.get $r) (i32.const 1))))
      (local.set $r (i32.or (local.get $r) (i32.const 2))))
    (i32.or (local.get $r) (i32.const 4)))
  ;; loop mit if und br_if auf die Schleife
  (func $d (param $n i32) (result i32) (local $i i32) (local $s i32)
    (loop $l
      (if (i32.rem_u (local.get $i) (i32.const 2))
        (then (local.set $s (i32.add (local.get $s) (local.get $i)))))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br_if $l (i32.lt_u (local.get $i) (local.get $n))))
    (local.get $s))

  (func (export "_start")
    (call $p (call $a (i32.const 1)) (i32.const 5))
    (call $p (call $a (i32.const 0)) (i32.const 9))
    (call $p (call $b (i32.const 1)) (i32.const 1))
    (call $p (call $b (i32.const 0)) (i32.const 2))
    (call $p (call $c (i32.const 1)) (i32.const 4))
    (call $p (call $c (i32.const 0)) (i32.const 7))
    (call $p (call $d (i32.const 10)) (i32.const 25))
    (call $ex (i32.const 0))))
