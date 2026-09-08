(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit" (func $exit (param i32)))
  (memory 1)
  (export "memory" (memory 0))
  (data (i32.const 200) "Hallo von WebAssembly auf OrientOS!\n")
  (data (i32.const 236) "Schleife+if gehen ok\n")
  (func (export "_start")
    (local $i i32) (local $s i32)
    (i32.store (i32.const 100) (i32.const 200))
    (i32.store (i32.const 104) (i32.const 35))
    (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 120)))
    (local.set $i (i32.const 1))
    (block $ende
      (loop $wieder
        (br_if $ende (i32.gt_s (local.get $i) (i32.const 10)))
        (local.set $s (i32.add (local.get $s) (local.get $i)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $wieder)))
    (if (i32.eq (local.get $s) (i32.const 55))
      (then
        (i32.store (i32.const 100) (i32.const 236))
        (i32.store (i32.const 104) (i32.const 21))
        (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 120)))))
    (call $exit (i32.const 0))))
