(module
  (import "wasi_snapshot_preview1" "fd_write" (func $fw (param i32 i32 i32 i32) (result i32)))
  (memory 1)
  (export "memory" (memory 0))
  (data (i32.const 500) "OK\n")
  (data (i32.const 510) "FEHLER\n")
  (func $p (param $x i32) (param $y i32)
    (if (i32.eq (local.get $x) (local.get $y))
      (then (i32.store (i32.const 100) (i32.const 500)) (i32.store (i32.const 104) (i32.const 3)))
      (else (i32.store (i32.const 100) (i32.const 510)) (i32.store (i32.const 104) (i32.const 7))))
    (drop (call $fw (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 120))))

  ;; DER FEHLER AUS f177 (dateitest): `br` auf eine AEUSSERE Schleife
  ;; aus einem geschachtelten Block heraus. Das heisst ZURUECK an den
  ;; Anfang der Schleife -- nicht hinter ihr Ende.
  (func $zurueck (param $n i32) (result i32) (local $i i32) (local $r i32)
    (block $raus
      (loop $lp
        (block $b1
          (block $b2
            (local.set $i (i32.add (local.get $i) (i32.const 1)))
            (br_if $raus (i32.gt_s (local.get $i) (i32.const 20)))   ;; Notbremse
            (br_if $b2 (i32.eq (local.get $n) (i32.const 0)))
            (br_if $b1 (i32.eq (local.get $n) (i32.const 1)))
            (local.set $r (i32.add (local.get $r) (i32.const 1000)))
            (br $raus))
          ;; hinter b2: zurueck an den Anfang der Schleife
          (local.set $r (i32.add (local.get $r) (i32.const 1)))
          (br_if $lp (i32.lt_s (local.get $i) (i32.const 3)))
          (br $raus))
        ;; hinter b1: ebenfalls zurueck, aber ueber ZWEI Ebenen
        (local.set $r (i32.add (local.get $r) (i32.const 100)))
        (br_if $lp (i32.lt_s (local.get $i) (i32.const 4)))))
    (local.get $r))

  ;; `br` auf eine Schleife aus DREI Ebenen heraus, mit Rest dahinter
  (func $tief (param $n i32) (result i32) (local $i i32) (local $r i32)
    (loop $l2
      (block $c1
        (block $c2
          (block $c3
            (local.set $i (i32.add (local.get $i) (i32.const 1)))
            (br_if $c3 (i32.gt_s (local.get $i) (i32.const 5)))
            (br $l2))                                   ;; zurueck von ganz innen
          (local.set $r (i32.add (local.get $r) (i32.const 7))))
        (local.set $r (i32.add (local.get $r) (i32.const 70))))
      (local.set $r (i32.add (local.get $r) (i32.const 700))))
    (i32.add (local.get $r) (local.get $i)))

  (func (export "_start")
    (call $p (call $zurueck (i32.const 0)) (i32.const 3))
    (call $p (call $zurueck (i32.const 1)) (i32.const 400))
    (call $p (call $zurueck (i32.const 2)) (i32.const 1000))
    (call $p (call $tief (i32.const 0)) (i32.const 783))
  )
)
