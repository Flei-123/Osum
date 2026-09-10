(module
  (import "wasi_snapshot_preview1" "path_open"
    (func $po (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fw (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit" (func $ex (param i32)))
  (memory 1)
  (export "memory" (memory 0))
  (data (i32.const 300) "/wasm-po-test.txt")
  (data (i32.const 400) "path_open ok\n")
  (data (i32.const 420) "path_open FEHLER\n")
  (func (export "_start") (local $rc i32)
    (local.set $rc
      (call $po (i32.const 3) (i32.const 0) (i32.const 300) (i32.const 17)
                (i32.const 1)                    ;; oflags CREAT
                (i64.const 66) (i64.const 66)    ;; rights READ|WRITE
                (i32.const 0) (i32.const 200)))  ;; fd nach 200
    (if (i32.eqz (local.get $rc))
      (then
        (i32.store (i32.const 100) (i32.const 400))
        (i32.store (i32.const 104) (i32.const 13)))
      (else
        (i32.store (i32.const 100) (i32.const 420))
        (i32.store (i32.const 104) (i32.const 17))))
    (drop (call $fw (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 120)))
    (call $ex (i32.const 0))))
