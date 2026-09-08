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

  (func $turm (param $n i32) (result i32) (local $r i32)
    (block $b0
      (block $b1
        (block $b2
          (block $b3
            (block $b4
              (block $b5
                (block $b6
                  (block $b7
                    (block $b8
                      (block $b9
                        (block $b10
                          (block $b11
                            (local.set $r (i32.const 1000))
                            (br_if $b0 (i32.eq (local.get $n) (i32.const 0)))
                            (br_if $b1 (i32.eq (local.get $n) (i32.const 1)))
                            (br_if $b2 (i32.eq (local.get $n) (i32.const 2)))
                            (br_if $b3 (i32.eq (local.get $n) (i32.const 3)))
                            (br_if $b4 (i32.eq (local.get $n) (i32.const 4)))
                            (br_if $b5 (i32.eq (local.get $n) (i32.const 5)))
                            (br_if $b6 (i32.eq (local.get $n) (i32.const 6)))
                            (br_if $b7 (i32.eq (local.get $n) (i32.const 7)))
                            (br_if $b8 (i32.eq (local.get $n) (i32.const 8)))
                            (br_if $b9 (i32.eq (local.get $n) (i32.const 9)))
                            (br_if $b10 (i32.eq (local.get $n) (i32.const 10)))
                            (br_if $b11 (i32.eq (local.get $n) (i32.const 11)))
                            (local.set $r (i32.add (local.get $r) (i32.const 7)))
                            (local.set $r (i32.add (local.get $r) (i32.const 11))))
                          (local.set $r (i32.add (local.get $r) (i32.const 10))))
                        (local.set $r (i32.add (local.get $r) (i32.const 512))))
                      (local.set $r (i32.add (local.get $r) (i32.const 256))))
                    (local.set $r (i32.add (local.get $r) (i32.const 128))))
                  (local.set $r (i32.add (local.get $r) (i32.const 64))))
                (local.set $r (i32.add (local.get $r) (i32.const 32))))
              (local.set $r (i32.add (local.get $r) (i32.const 16))))
            (local.set $r (i32.add (local.get $r) (i32.const 8))))
          (local.set $r (i32.add (local.get $r) (i32.const 4))))
        (local.set $r (i32.add (local.get $r) (i32.const 2))))
      (local.set $r (i32.add (local.get $r) (i32.const 1))))
    (local.get $r))

  (func $tsl (param $n i32) (result i32) (local $r i32) (local $i i32)
    (block $c0
      (block $c1
        (block $c2
          (block $c3
            (block $c4
              (loop $lp
                (block $d0
                  (block $d1
                    (block $d2
                      (block $d3
                        (local.set $i (i32.add (local.get $i) (i32.const 1)))
                        (br_if $lp (i32.lt_s (local.get $i) (i32.const 3)))
                        (br_if $d1 (i32.eq (local.get $n) (i32.const 1)))
                        (br_if $c0 (i32.eq (local.get $n) (i32.const 2)))
                        (local.set $r (i32.const 100))
                        (local.set $r (i32.add (local.get $r) (i32.const 8))))
                      (local.set $r (i32.add (local.get $r) (i32.const 4))))
                    (local.set $r (i32.add (local.get $r) (i32.const 2))))
                  (local.set $r (i32.add (local.get $r) (i32.const 1))))
                )
              (local.set $r (i32.add (local.get $r) (i32.const 5000))))
            (local.set $r (i32.add (local.get $r) (i32.const 4000))))
          (local.set $r (i32.add (local.get $r) (i32.const 3000))))
        (local.set $r (i32.add (local.get $r) (i32.const 2000))))
      (local.set $r (i32.add (local.get $r) (i32.const 1000))))
    (local.get $r) (i32.add (local.get $i) (i32.const 0)) (drop))


  ;; Rohausgabe: vier Oktette des Wertes. So sieht der Vergleich
  ;; Deuter/AOT den WERT, nicht nur ein OK.
  (func $show (param $v i32)
    (i32.store (i32.const 200) (local.get $v))
    (i32.store (i32.const 100) (i32.const 200))
    (i32.store (i32.const 104) (i32.const 4))
    (drop (call $fw (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 120))))

  ;; Sprung in eine Turmebene aus einer INNEREN Schleife heraus.
  ;; Genau hier reicht `continue` nicht: es wuerde die innere Schleife
  ;; fortsetzen, nicht den Verteiler.
  (func $tinner (param $n i32) (result i32) (local $r i32) (local $i i32)
    (block $a0 (block $a1 (block $a2 (block $a3 (block $a4
    (block $a5 (block $a6 (block $a7 (block $a8 (block $a9
    (block $a10 (block $a11
      (local.set $r (i32.const 1000))
      (loop $ll
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br_if $a3 (i32.eq (local.get $n) (i32.const 3)))
        (block $inner
          (br_if $inner (i32.eq (local.get $n) (i32.const 9)))
          (br_if $a7 (i32.eq (local.get $n) (i32.const 7))))
        (br_if $a9 (i32.eq (local.get $n) (i32.const 9)))
        (br_if $ll (i32.lt_s (local.get $i) (i32.const 2)))
        (br_if $a11 (i32.eq (local.get $n) (i32.const 11))))
      (local.set $r (i32.add (local.get $r) (i32.const 7)))
    ) (local.set $r (i32.add (local.get $r) (i32.const 11))))
      (local.set $r (i32.add (local.get $r) (i32.const 512))))
      (local.set $r (i32.add (local.get $r) (i32.const 256))))
      (local.set $r (i32.add (local.get $r) (i32.const 128))))
      (local.set $r (i32.add (local.get $r) (i32.const 64))))
      (local.set $r (i32.add (local.get $r) (i32.const 32))))
      (local.set $r (i32.add (local.get $r) (i32.const 16))))
      (local.set $r (i32.add (local.get $r) (i32.const 8))))
      (local.set $r (i32.add (local.get $r) (i32.const 4))))
      (local.set $r (i32.add (local.get $r) (i32.const 2))))
      (local.set $r (i32.add (local.get $r) (i32.const 1))))
    (local.get $r))

  (func (export "_start")
    (call $p (call $turm (i32.const 0)) (i32.const 1000))
    (call $p (call $turm (i32.const 1)) (i32.const 1001))
    (call $p (call $turm (i32.const 2)) (i32.const 1003))
    (call $p (call $turm (i32.const 3)) (i32.const 1007))
    (call $p (call $turm (i32.const 4)) (i32.const 1015))
    (call $p (call $turm (i32.const 5)) (i32.const 1031))
    (call $p (call $turm (i32.const 6)) (i32.const 1063))
    (call $p (call $turm (i32.const 7)) (i32.const 1127))
    (call $p (call $turm (i32.const 8)) (i32.const 1255))
    (call $p (call $turm (i32.const 9)) (i32.const 1511))
    (call $p (call $turm (i32.const 10)) (i32.const 2023))
    (call $p (call $turm (i32.const 11)) (i32.const 2033))
    (call $p (call $tsl (i32.const 0)) (call $tsl (i32.const 0)))
    (call $p (call $tsl (i32.const 1)) (call $tsl (i32.const 1)))
    (call $p (call $tsl (i32.const 2)) (call $tsl (i32.const 2)))
    (call $show (call $tinner (i32.const 0)))
    (call $show (call $tinner (i32.const 3)))
    (call $show (call $tinner (i32.const 7)))
    (call $show (call $tinner (i32.const 9)))
    (call $show (call $tinner (i32.const 11)))
  )
)
